-- Test script for Arabic locale-specific tokenizer

-- Load the locale-specific tokenizer (from the build directory)
.load ./build/libfts5_icu_ar.so

-- Create a test table using the Arabic tokenizer
CREATE VIRTUAL TABLE test_ar USING fts5(
    content,
    tokenize = 'icu_ar'
);

-- Insert some Arabic text
INSERT INTO test_ar(content) VALUES ('اختبار اللغة العربية');
INSERT INTO test_ar(content) VALUES ('رسالة تجريبية');

-- Query the table
SELECT * FROM test_ar WHERE test_ar MATCH 'اختبار';
SELECT * FROM test_ar WHERE test_ar MATCH 'العربية';