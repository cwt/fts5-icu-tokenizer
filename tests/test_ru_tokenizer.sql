-- Test script for Russian locale-specific tokenizer

-- Load the locale-specific tokenizer (from the build directory)
.load ./build/libfts5_icu_ru.so

-- Create a test table using the Russian tokenizer
CREATE VIRTUAL TABLE test_ru USING fts5(
    content,
    tokenize = 'icu_ru'
);

-- Insert some Russian text
INSERT INTO test_ru(content) VALUES ('Тестирование русского языка');
INSERT INTO test_ru(content) VALUES ('Пример сообщения');

-- Query the table
SELECT * FROM test_ru WHERE test_ru MATCH 'Тестирование';
SELECT * FROM test_ru WHERE test_ru MATCH 'русского';