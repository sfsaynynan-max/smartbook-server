require('dotenv').config();
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const { pool, initDB } = require('./db');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3000;
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY;

// Health Check
app.get('/', (req, res) => {
  res.json({ status: 'SmartBook Server Running 🚀' });
});

// جلب نص الكتاب
app.get('/book-text/:bookId', async (req, res) => {
  const { bookId } = req.params;

  const urls = [
    `https://www.gutenberg.org/cache/epub/${bookId}/pg${bookId}.txt`,
    `https://www.gutenberg.org/files/${bookId}/${bookId}-0.txt`,
    `https://www.gutenberg.org/files/${bookId}/${bookId}.txt`,
  ];

  for (const url of urls) {
    try {
      const response = await axios.get(url, {
        timeout: 15000,
        responseType: 'text',
      });
      if (response.status === 200 && response.data.length > 1000) {
        const paragraphs = extractParagraphs(response.data);
        if (paragraphs.length > 0) {
          return res.json({ success: true, paragraphs });
        }
      }
    } catch (e) {
      continue;
    }
  }

  return res.json({ success: false, paragraphs: [] });
});

function extractParagraphs(text) {
  let startIndex = 0;
  const startMarkers = [
    '*** START OF THE PROJECT GUTENBERG',
    '*** START OF THIS PROJECT GUTENBERG',
    'CHAPTER I',
    'Chapter I',
    'CHAPTER 1',
    'Chapter 1',
  ];
  for (const marker of startMarkers) {
    const idx = text.indexOf(marker);
    if (idx !== -1) {
      startIndex = idx + marker.length;
      break;
    }
  }

  let endIndex = text.length;
  const endMarkers = [
    '*** END OF THE PROJECT GUTENBERG',
    '*** END OF THIS PROJECT GUTENBERG',
    'End of the Project Gutenberg',
  ];
  for (const marker of endMarkers) {
    const idx = text.indexOf(marker, startIndex);
    if (idx !== -1) {
      endIndex = idx;
      break;
    }
  }

  const content = text.substring(startIndex, endIndex);
  return content
    .split(/\n\s*\n/)
    .map(p => p.trim().replace(/\s+/g, ' ').replace(/_/g, ''))
    .filter(p => p.length > 80 && !p.startsWith('***'))
    .slice(0, 40);
}

// ترجمة فقرة واحدة
app.post('/translate', async (req, res) => {
  const { bookId, paragraphIndex, text, targetLanguage } = req.body;

  if (!bookId || !text || !targetLanguage) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  try {
    const cached = await pool.query(
      `SELECT translated_text FROM translations 
       WHERE book_id = $1 AND language = $2 AND paragraph_index = $3`,
      [bookId, targetLanguage, paragraphIndex]
    );

    if (cached.rows.length > 0) {
      return res.json({
        translated: cached.rows[0].translated_text,
        cached: true,
      });
    }

    const response = await axios.post(
      'https://api.deepseek.com/v1/chat/completions',
      {
        model: 'deepseek-chat',
        messages: [
          {
            role: 'system',
            content: `You are a professional literary translator. Translate the given text to ${targetLanguage}. Keep the literary style and tone. Return ONLY the translated text, nothing else.`,
          },
          { role: 'user', content: text },
        ],
        max_tokens: 1000,
        temperature: 0.3,
      },
      {
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${DEEPSEEK_API_KEY}`,
        },
      }
    );

    const translated = response.data.choices[0].message.content;

    await pool.query(
      `INSERT INTO translations 
       (book_id, language, paragraph_index, original_text, translated_text)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (book_id, language, paragraph_index) DO NOTHING`,
      [bookId, targetLanguage, paragraphIndex, text, translated]
    );

    return res.json({ translated, cached: false });
  } catch (error) {
    console.error('Translation error:', error.message);
    return res.status(500).json({ error: 'Translation failed' });
  }
});

// ترجمة كتاب كامل
app.post('/translate-book', async (req, res) => {
  const { bookId, paragraphs, targetLanguage } = req.body;

  if (!bookId || !paragraphs || !targetLanguage) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  try {
    const results = [];

    for (let i = 0; i < paragraphs.length; i++) {
      const text = paragraphs[i];

      const cached = await pool.query(
        `SELECT translated_text FROM translations 
         WHERE book_id = $1 AND language = $2 AND paragraph_index = $3`,
        [bookId, targetLanguage, i]
      );

      if (cached.rows.length > 0) {
        results.push({
          index: i,
          translated: cached.rows[0].translated_text,
          cached: true,
        });
        continue;
      }

      try {
        const response = await axios.post(
          'https://api.deepseek.com/v1/chat/completions',
          {
            model: 'deepseek-chat',
            messages: [
              {
                role: 'system',
                content: `Translate to ${targetLanguage}. Return ONLY the translation.`,
              },
              { role: 'user', content: text },
            ],
            max_tokens: 1000,
            temperature: 0.3,
          },
          {
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${DEEPSEEK_API_KEY}`,
            },
          }
        );

        const translated = response.data.choices[0].message.content;

        await pool.query(
          `INSERT INTO translations 
           (book_id, language, paragraph_index, original_text, translated_text)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (book_id, language, paragraph_index) DO NOTHING`,
          [bookId, targetLanguage, i, text, translated]
        );

        results.push({ index: i, translated, cached: false });
        await new Promise(r => setTimeout(r, 300));
      } catch (err) {
        results.push({ index: i, translated: text, cached: false });
      }
    }

    return res.json({ results, total: paragraphs.length });
  } catch (error) {
    console.error('Book translation error:', error.message);
    return res.status(500).json({ error: 'Translation failed' });
  }
});

// جلب ترجمة محفوظة
app.get('/translation/:bookId/:language', async (req, res) => {
  const { bookId, language } = req.params;

  try {
    const result = await pool.query(
      `SELECT paragraph_index, translated_text 
       FROM translations 
       WHERE book_id = $1 AND language = $2 
       ORDER BY paragraph_index ASC`,
      [bookId, language]
    );

    if (result.rows.length === 0) {
      return res.json({ exists: false, paragraphs: [] });
    }

    const paragraphs = result.rows.map(r => r.translated_text);
    return res.json({ exists: true, paragraphs });
  } catch (error) {
    return res.status(500).json({ error: 'Database error' });
  }
});

initDB().then(() => {
  app.listen(PORT, () => {
    console.log(`🚀 SmartBook Server running on port ${PORT}`);
  });
});
