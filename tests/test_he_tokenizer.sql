-- Test script for Hebrew locale-specific tokenizer

-- Load the locale-specific tokenizer (from the build directory)
.load ./build/libfts5_icu_he.so

-- Create a test table using the Hebrew tokenizer
CREATE VIRTUAL TABLE test_he USING fts5(
    content,
    tokenize = 'icu_he'
);

-- Insert some Hebrew text
INSERT INTO test_he(content) VALUES ('בדיקה של שפת העברית');
INSERT INTO test_he(content) VALUES ('הודעה לדוגמה');

-- Query the table
SELECT * FROM test_he WHERE test_he MATCH 'בדיקה';
SELECT * FROM test_he WHERE test_he MATCH 'העברית';