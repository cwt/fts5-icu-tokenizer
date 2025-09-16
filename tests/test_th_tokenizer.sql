-- Test script for Thai locale-specific tokenizer

-- Load the locale-specific tokenizer (from the build directory)
.load ./build/libfts5_icu_th.so

-- Create a test table using the Thai tokenizer
CREATE VIRTUAL TABLE test_th USING fts5(
    content,
    tokenize = 'icu_th'
);

-- Insert some Thai text
INSERT INTO test_th(content) VALUES ('การทดสอบภาษาไทย');
INSERT INTO test_th(content) VALUES ('ตัวอย่างข้อความภาษาไทย');

-- Query the table
SELECT * FROM test_th WHERE test_th MATCH 'ทดสอบ';
SELECT * FROM test_th WHERE test_th MATCH 'ภาษาไทย';