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

// =============================
// Health Check
// =============================
app.get('/', (req, res) => {
  res.json({ status: 'SmartBook Server Running 🚀' });
});

// =============================
// ترجمة فقرة واحدة مع كاش
// =============================
app.post('/translate', async (req, res) => {
  const { bookId, paragraphIndex, text, targetLanguage } = req.body;

  if (!bookId || !text || !targetLanguage) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  try {
    // ١ — تحقق من الكاش في قاعدة البيانات
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

    // ٢ — إذا لم توجد ترجمة — نطلب من DeepSeek
    const response = await axios.post(
      'https://api.deepseek.com/v1/chat/completions',
      {
        model: 'deepseek-chat',
        messages: [
          {
            role: 'system',
            content: `You are a professional literary translator. 
Translate the given text to ${targetLanguage}. 
Keep the literary style and tone. 
Return ONLY the translated text, nothing else.`,
          },
          {
            role: 'user',
            content: text,
          },
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

    // ٣ — احفظ في قاعدة البيانات
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

// =============================
// ترجمة كتاب كامل دفعة واحدة
// =============================
app.post('/translate-book', async (req, res) => {
  const { bookId, paragraphs, targetLanguage } = req.body;

  if (!bookId || !paragraphs || !targetLanguage) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  try {
    const results = [];

    for (let i = 0; i < paragraphs.length; i++) {
      const text = paragraphs[i];

      // تحقق من الكاش
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

      // ترجمة جديدة
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

        // احفظ
        await pool.query(
          `INSERT INTO translations 
           (book_id, language, paragraph_index, original_text, translated_text)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (book_id, language, paragraph_index) DO NOTHING`,
          [bookId, targetLanguage, i, text, translated]
        );

        results.push({ index: i, translated, cached: false });

        // تأخير لتجنب rate limiting
        await new Promise((r) => setTimeout(r, 300));
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

// =============================
// جلب ترجمة محفوظة
// =============================
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

    const paragraphs = result.rows.map((r) => r.translated_text);
    return res.json({ exists: true, paragraphs });
  } catch (error) {
    return res.status(500).json({ error: 'Database error' });
  }
});

// =============================
// تشغيل السيرفر
// =============================
initDB().then(() => {
  app.listen(PORT, () => {
    console.log(`🚀 SmartBook Server running on port ${PORT}`);
  });
});
