const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

async function initDB() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS translations (
        id SERIAL PRIMARY KEY,
        book_id TEXT NOT NULL,
        language TEXT NOT NULL,
        paragraph_index INTEGER NOT NULL,
        original_text TEXT NOT NULL,
        translated_text TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(book_id, language, paragraph_index)
      );
    `);
    await pool.query(`
      CREATE TABLE IF NOT EXISTS book_texts (
        id SERIAL PRIMARY KEY,
        book_id TEXT NOT NULL UNIQUE,
        paragraphs JSONB NOT NULL,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    console.log('✅ Database ready');
  } catch (error) {
    console.error('DB init error:', error.message);
    // لا نوقف السيرفر عند خطأ DB
  }
}

module.exports = { pool, initDB };
