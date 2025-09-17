-- Provide the path to the specific library in your build directory.
.load ./build/libfts5_icu.so

-- Create a virtual table using the correctly named tokenizer
CREATE VIRTUAL TABLE documents USING fts5(
    content,
    tokenize = 'icu'
);

-- Insert and query text
SELECT 'INSERT: 甜蜜蜜,你笑得甜蜜蜜-หวานปานน้ำผึ้ง,ยิ้มของคุณช่างหวานปานน้ำผึ้ง';
INSERT INTO documents(content) VALUES ('甜蜜蜜,你笑得甜蜜蜜-หวานปานน้ำผึ้ง,ยิ้มของคุณช่างหวานปานน้ำผึ้ง');
SELECT '-------------------------------------------------------------';
SELECT 'SEARCH: หวน';
SELECT 'RESULT:', (SELECT * FROM documents WHERE documents MATCH 'หวน');
SELECT '-------------------------------------------------------------';
SELECT 'SEARCH: ยิม';
SELECT 'RESULT:', (SELECT * FROM documents WHERE documents MATCH 'ยิม');
SELECT '-------------------------------------------------------------';
SELECT 'SEARCH: ยม';
SELECT 'RESULT:', (SELECT * FROM documents WHERE documents MATCH 'ยม');
SELECT '-------------------------------------------------------------';
SELECT 'SEARCH: ยิ้ม';
SELECT 'RESULT:', (SELECT * FROM documents WHERE documents MATCH 'ยิ้ม');
SELECT '-------------------------------------------------------------';
SELECT 'SEARCH: หวาน';
SELECT 'RESULT:', (SELECT * FROM documents WHERE documents MATCH 'หวาน');
SELECT '-------------------------------------------------------------';
SELECT 'SEARCH: 甜蜜蜜';
SELECT 'RESULT:', (SELECT * FROM documents WHERE documents MATCH '甜蜜蜜');
SELECT '-------------------------------------------------------------';
