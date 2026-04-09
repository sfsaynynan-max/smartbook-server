const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

// إنشاء جدول الترجمات
async function initDB() {
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
  console.log('✅ Database ready');
}

module.exports = { pool, initDB };
