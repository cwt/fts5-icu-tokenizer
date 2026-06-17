-- Test script for robust tokenization of malformed UTF-8 inputs

-- Load the universal tokenizer
.load ./build/libfts5_icu

-- Create an FTS5 table
CREATE VIRTUAL TABLE documents_malformed USING fts5(
    content,
    tokenize = 'icu'
);

-- Insert a text containing an invalid UTF-8 byte (0xFF) in the middle of "hello" and "world"
-- Under the old implementation, this would throw an error during insertion.
SELECT '--- Inserting malformed UTF-8 ---';
INSERT INTO documents_malformed(content) VALUES (CAST(x'68656c6c6fff6f726c64' AS TEXT));

-- Retrieve and verify the inserted record
SELECT '--- Querying retrieved text ---';
SELECT content FROM documents_malformed;

-- Verify we can search for "hello" and "world" separately around the invalid byte
SELECT '--- Searching for "hello" ---';
SELECT * FROM documents_malformed WHERE documents_malformed MATCH 'hello';

SELECT '--- Searching for "orld" ---';
SELECT * FROM documents_malformed WHERE documents_malformed MATCH 'orld';
