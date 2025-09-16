-- Test script for universal tokenizer

-- Load the universal tokenizer (from the build directory)
.load ./build/libfts5_icu.so

-- Create a test table using the universal tokenizer
CREATE VIRTUAL TABLE test_universal USING fts5(
    content,
    tokenize = 'icu'
);

-- Insert text in different languages
INSERT INTO test_universal(content) VALUES ('中文测试');
INSERT INTO test_universal(content) VALUES ('Français');
INSERT INTO test_universal(content) VALUES ('русский');
INSERT INTO test_universal(content) VALUES ('العربية');

-- Query the table
SELECT * FROM test_universal WHERE test_universal MATCH '测试';
SELECT * FROM test_universal WHERE test_universal MATCH 'francais';
SELECT * FROM test_universal WHERE test_universal MATCH 'russkii';
SELECT * FROM test_universal WHERE test_universal MATCH 'العربية';