-- Test script for robust tokenization of malformed UTF-8 inputs

-- Load the universal tokenizer
.load ./zig-out/lib/libfts5_icu

-- Create an FTS5 table
CREATE VIRTUAL TABLE documents_malformed USING fts5(
    content,
    tokenize = 'icu'
);

-- Insert a text containing invalid UTF-8 bytes (0xFF)
SELECT '--- Inserting malformed UTF-8 ---';
INSERT INTO documents_malformed(content) VALUES (CAST(x'68656c6c6f20ff20776f726c64' AS TEXT));
INSERT INTO documents_malformed(content) VALUES (CAST(x'68656c6c6fff6f726c64' AS TEXT));

-- Retrieve and verify the inserted record
SELECT '--- Querying retrieved text ---';
SELECT content FROM documents_malformed;

-- Verify we can search for "hello" and "world"
SELECT '--- Searching for "hello" ---';
SELECT content FROM documents_malformed WHERE documents_malformed MATCH 'hello';

SELECT '--- Searching for "world" ---';
SELECT content FROM documents_malformed WHERE documents_malformed MATCH 'world';

-- Verify prefix search "hello*" on concatenated malformed string
SELECT '--- Searching for "hello*" (prefix search) ---';
SELECT content FROM documents_malformed WHERE documents_malformed MATCH 'hello*';
