-- Test script for ja locale-specific tokenizer

-- Load the locale-specific tokenizer (from the build directory)
.load ./build/libfts5_icu_ja.so

-- Create a test table using the Japanese tokenizer
CREATE VIRTUAL TABLE test_ja USING fts5(
    content,
    tokenize = 'icu_ja'
);

-- Insert some Japanese text
INSERT INTO test_ja(content) VALUES ('日本語のテスト');
INSERT INTO test_ja(content) VALUES ('ひらがなとカタカナのテスト');

-- Query the table
SELECT * FROM test_ja WHERE test_ja MATCH '日本語';
SELECT * FROM test_ja WHERE test_ja MATCH 'テスト';