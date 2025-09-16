-- Test script for Korean locale-specific tokenizer

-- Load the locale-specific tokenizer (from the build directory)
.load ./build/libfts5_icu_ko.so

-- Create a test table using the Korean tokenizer
CREATE VIRTUAL TABLE test_ko USING fts5(
    content,
    tokenize = 'icu_ko'
);

-- Insert some Korean text
INSERT INTO test_ko(content) VALUES ('한국어 테스트');
INSERT INTO test_ko(content) VALUES ('테스트 메시지');

-- Query the table
SELECT * FROM test_ko WHERE test_ko MATCH '한국어';
SELECT * FROM test_ko WHERE test_ko MATCH '테스트';