-- Test script for zh locale-specific tokenizer

-- Load the locale-specific tokenizer (from the build directory)
.load ./build/libfts5_icu_zh.so

-- Create a test table using the Chinese tokenizer
CREATE VIRTUAL TABLE test_zh USING fts5(
    content,
    tokenize = 'icu_zh'
);

-- Insert some Chinese text
INSERT INTO test_zh(content) VALUES ('中文测试');
INSERT INTO test_zh(content) VALUES ('繁體中文測試');

-- Query the table
SELECT * FROM test_zh WHERE test_zh MATCH '中文';
SELECT * FROM test_zh WHERE test_zh MATCH '测试';