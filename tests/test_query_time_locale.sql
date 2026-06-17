-- Test script for query-time and insert-time dynamic locale tokenization

-- Load the universal tokenizer
.load ./build/libfts5_icu

-- Create an FTS5 table with locale=1 support enabled
CREATE VIRTUAL TABLE documents_dynamic USING fts5(
    content,
    tokenize = 'icu',
    locale = 1
);

-- Insert Thai text using fts5_locale with 'th' locale
INSERT INTO documents_dynamic(content) VALUES (fts5_locale('th', 'การทดสอบภาษาไทยในระบบค้นหา'));

-- Query using fts5_locale with 'th'
SELECT '--- Query with TH locale (word: ภาษา) ---';
SELECT * FROM documents_dynamic WHERE documents_dynamic MATCH fts5_locale('th', 'ภาษา');

SELECT '--- Query with TH locale (word: ระบบ) ---';
SELECT * FROM documents_dynamic WHERE documents_dynamic MATCH fts5_locale('th', 'ระบบ');

-- Insert Chinese text using fts5_locale with 'zh' locale
INSERT INTO documents_dynamic(content) VALUES (fts5_locale('zh', '繁體中文測試'));

-- Query using fts5_locale with 'zh'
SELECT '--- Query with ZH locale (word: 测试 - Simplified query against Traditional document) ---';
SELECT * FROM documents_dynamic WHERE documents_dynamic MATCH fts5_locale('zh', '测试');
