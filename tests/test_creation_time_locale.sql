-- Test script for table creation-time custom locale arguments

-- Load the universal tokenizer
.load ./build/libfts5_icu

-- Create an FTS5 table with locale set to 'th' at table creation time
CREATE VIRTUAL TABLE documents_th USING fts5(
    content,
    tokenize = 'icu th'
);

-- Insert Thai text
INSERT INTO documents_th(content) VALUES ('การทดสอบภาษาไทยในระบบค้นหา');

-- Query using standard MATCH (since table is configured with 'th' locale, it should segment it properly by default)
SELECT '--- Query with TH locale set at creation time (word: ภาษา) ---';
SELECT * FROM documents_th WHERE documents_th MATCH 'ภาษา';

SELECT '--- Query with TH locale set at creation time (word: ระบบ) ---';
SELECT * FROM documents_th WHERE documents_th MATCH 'ระบบ';
