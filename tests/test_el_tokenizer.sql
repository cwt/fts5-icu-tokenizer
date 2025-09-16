-- Test script for Greek locale-specific tokenizer

-- Load the locale-specific tokenizer (from the build directory)
.load ./build/libfts5_icu_el.so

-- Create a test table using the Greek tokenizer
CREATE VIRTUAL TABLE test_el USING fts5(
    content,
    tokenize = 'icu_el'
);

-- Insert some Greek text
INSERT INTO test_el(content) VALUES ('Δοκιμή της ελληνικής γλώσσας');
INSERT INTO test_el(content) VALUES ('Παράδειγμα μηνύματος');

-- Query the table
SELECT * FROM test_el WHERE test_el MATCH 'Δοκιμή';
SELECT * FROM test_el WHERE test_el MATCH 'ελληνικής';