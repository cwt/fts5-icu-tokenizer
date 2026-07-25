-- Test script for ja locale-specific tokenizer

-- Load the Japanese tokenizer (from zig-out directory)
.load ./zig-out/lib/libfts5_icu_ja

-- Create a test table using the Japanese tokenizer
CREATE VIRTUAL TABLE test_ja_v2 USING fts5(
    content,
    tokenize = 'icu_ja'
);

-- Insert some Japanese text
INSERT INTO test_ja_v2(content) VALUES ('日本語のテスト');
INSERT INTO test_ja_v2(content) VALUES ('ひらがなとカタカナのテスト');

-- Query the table
SELECT * FROM test_ja_v2 WHERE test_ja_v2 MATCH '日本語';
SELECT * FROM test_ja_v2 WHERE test_ja_v2 MATCH 'テスト';