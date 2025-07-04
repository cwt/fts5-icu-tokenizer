# FTS5 ICU Tokenizer for SQLite

This project provides a custom FTS5 tokenizer for SQLite that uses the International Components for Unicode (ICU) library to provide robust word segmentation for various languages.

It is written in C for maximum stability and performance, making it suitable for high-availability systems. The target locale is configurable at build time.

## Prerequisites

Before you begin, ensure you have the following installed on your system:

- **CMake** (version 3.10 or higher)
- A **C Compiler** (GCC, Clang, or MSVC)
- **SQLite3** development libraries (`libsqlite3-dev` on Debian/Ubuntu, `sqlite-devel` on Fedora/CentOS)
- **ICU** development libraries (`libicu-dev` on Debian/Ubuntu, `libicu-devel` on Fedora/CentOS)

## Building and Installing

This project uses a standard CMake build process. The target locale can be specified using the `LOCALE` variable.

### 1. Create a build directory

It's best practice to build the project in a separate directory.

```bash
mkdir build
cd build
```

### 2. Configure the project with CMake

This step generates the native build files (e.g., Makefiles). You can specify the locale here.

**Example for Thai (`th`):** This will produce `fts5_icu_th.so` and register the tokenizer as `icu_th`.

```bash
cmake .. -DLOCALE=th
```

**Example for Chinese (`cn`):** This will produce `fts5_icu_cn.so` and register the tokenizer as `icu_cn`.

```bash
cmake .. -DLOCALE=cn
```

**Example for a Universal Tokenizer:** If you omit the `LOCALE` option, it will build a generic tokenizer named `fts5_icu.so` that uses the default ICU word breaker and registers as `icu`.

```bash
cmake ..
```

### 3. Compile the project

```bash
cmake --build .
```

_(Alternatively, on Linux/macOS, you can just run `make`)_

### 4. Install the library (optional)

This will copy the compiled shared library to a standard system location (e.g., `/usr/local/lib`).

```bash
sudo cmake --build . --target install
```

_(Alternatively, on Linux/macOS, you can just run `sudo make install`)_

## Usage

After compiling, you can load the specific tokenizer you built into SQLite.

**Example for the Thai Tokenizer:**

```sql
-- Provide the path to the specific library in your build directory.
.load ./build/fts5_icu_th.so

-- Create a virtual table using the correctly named tokenizer
CREATE VIRTUAL TABLE documents_th USING fts5(
    content,
    tokenize = 'icu_th'
);

-- Insert and query Thai text
INSERT INTO documents_th(content) VALUES ('การทดสอบภาษาไทยในระบบค้นหา');
SELECT * FROM documents_th WHERE documents_th MATCH 'ภาษา';
```

**Example for the Universal Tokenizer:**

```sql
-- Provide the path to the specific library in your build directory.
.load ./build/fts5_icu.so

-- Create a virtual table using the correctly named tokenizer
CREATE VIRTUAL TABLE documents USING fts5(
    content,
    tokenize = 'icu'
);

-- Insert and query text
INSERT INTO documents(content) VALUES ('甜蜜蜜,你笑得甜蜜蜜-หวานปานน้ำผึ้ง,ยิ้มของคุณช่างหวานปานน้ำผึ้ง');
SELECT * FROM documents WHERE documents MATCH 'หวาน';
SELECT * FROM documents WHERE documents MATCH '甜蜜蜜';
```
