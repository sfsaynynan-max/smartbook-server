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

app.get('/', (req, res) => {
  res.json({ status: 'SmartBook Server Running 🚀' });
});

app.get('/book-text/:bookId', async (req, res) => {
  const { bookId } = req.params;

  try {
    const cached = await pool.query(
      'SELECT paragraphs FROM book_texts WHERE book_id = $1',
      [bookId]
    );

    if (cached.rows.length > 0) {
      return res.json({
        success: true,
        paragraphs: cached.rows[0].paragraphs,
        cached: true,
      });
    }

    const urls = [
      `https://www.gutenberg.org/cache/epub/${bookId}/pg${bookId}.txt`,
      `https://www.gutenberg.org/files/${bookId}/${bookId}-0.txt`,
      `https://www.gutenberg.org/files/${bookId}/${bookId}.txt`,
    ];

    let paragraphs = [];
    for (const url of urls) {
      try {
        const response = await axios.get(url, {
          timeout: 20000,
          responseType: 'text',
        });
        if (response.status === 200 && response.data.length > 1000) {
          paragraphs = extractParagraphs(response.data);
          if (paragraphs.length > 0) break;
        }
      } catch (e) {
        continue;
      }
    }

    if (paragraphs.length === 0) {
      return res.json({ success: false, paragraphs: [] });
    }

    try {
      await pool.query(
        `INSERT INTO book_texts (book_id, paragraphs)
         VALUES ($1, $2)
         ON CONFLICT (book_id) DO NOTHING`,
        [bookId, JSON.stringify(paragraphs)]
      );
    } catch (e) {
      console.error('Cache save error:', e.message);
    }

    return res.json({ success: true, paragraphs, cached: false });

  } catch (error) {
    console.error('Error:', error.message);
    return res.status(500).json({ success: false, paragraphs: [] });
  }
});

app.post('/translate-book', async (req, res) => {
  const { bookId, paragraphs, targetLanguage } = req.body;

  if (!bookId || !paragraphs || !targetLanguage) {
    return res.status(400).json({ error: 'Missing fields' });
  }

  try {
    const cached = await pool.query(
      `SELECT paragraph_index, translated_text 
       FROM translations 
       WHERE book_id = $1 AND language = $2 
       ORDER BY paragraph_index ASC`,
      [bookId, targetLanguage]
    );

    if (cached.rows.length > 0) {
      return res.json({
        success: true,
        paragraphs: cached.rows.map(r => r.translated_text),
        cached: true,
      });
    }

    const results = [];
    for (let i = 0; i < paragraphs.length; i++) {
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
              { role: 'user', content: paragraphs[i] },
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
          [bookId, targetLanguage, i, paragraphs[i], translated]
        );

        results.push(translated);
        await new Promise(r => setTimeout(r, 200));
      } catch (err) {
        results.push(paragraphs[i]);
      }
    }

    return res.json({ success: true, paragraphs: results, cached: false });
  } catch (error) {
    return res.status(500).json({ error: 'Translation failed' });
  }
});

app.get('/translation/:bookId/:language', async (req, res) => {
  const { bookId, language } = req.params;
  try {
    const result = await pool.query(
      `SELECT translated_text FROM translations 
       WHERE book_id = $1 AND language = $2 
       ORDER BY paragraph_index ASC`,
      [bookId, language]
    );
    if (result.rows.length === 0) {
      return res.json({ exists: false, paragraphs: [] });
    }
    return res.json({
      exists: true,
      paragraphs: result.rows.map(r => r.translated_text),
    });
  } catch (error) {
    return res.status(500).json({ error: 'Database error' });
  }
});

function extractParagraphs(text) {
  let startIndex = 0;
  const startMarkers = [
    '*** START OF THE PROJECT GUTENBERG',
    '*** START OF THIS PROJECT GUTENBERG',
    'CHAPTER I', 'Chapter I',
    'CHAPTER 1', 'Chapter 1',
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
  ];
  for (const marker of endMarkers) {
    const idx = text.indexOf(marker, startIndex);
    if (idx !== -1) {
      endIndex = idx;
      break;
    }
  }

  return text
    .substring(startIndex, endIndex)
    .split(/\n\s*\n/)
    .map(p => p.trim().replace(/\s+/g, ' ').replace(/_/g, ''))
    .filter(p => p.length > 80 && !p.startsWith('***'))
    .slice(0, 40);
}

// السيرفر يبدأ أولاً ثم DB
app.listen(PORT, () => {
  console.log(`🚀 SmartBook Server running on port ${PORT}`);
});

initDB();
