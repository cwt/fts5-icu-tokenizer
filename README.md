# FTS5 ICU Tokenizer for SQLite

This project provides custom FTS5 tokenizers for SQLite that use the International Components for Unicode (ICU) library to provide robust word segmentation for various languages.

The implementation fully complies with the FTS5 v2 API specifications and is written in C for maximum stability and performance, making it suitable for high-availability systems. The target locale is configurable at build time, with support for both universal and locale-specific tokenizers.

## Prerequisites

Before you begin, ensure you have the following installed on your system:

- **CMake** (version 3.10 or higher)
- A **C Compiler** (GCC, Clang, or MSVC)
- **SQLite3** development libraries (`libsqlite3-dev` on Debian/Ubuntu, `sqlite-devel` on Fedora/CentOS)
- **ICU** development libraries (`libicu-dev` on Debian/Ubuntu, `libicu-devel` on Fedora/CentOS)

## Building and Installing

This project uses a standard CMake build process. The target locale can be specified using the `LOCALE` variable.

### Quick Build and Test

For convenience, this project includes scripts to build and test all supported locales:

```bash
# Build all tokenizers
./scripts/build_all.sh

# Test all tokenizers
./scripts/test_all.sh
```

For detailed information about building and testing, see [docs/BUILD_TEST_README.md](docs/BUILD_TEST_README.md).

### Building Individual Locales

You can build individual locales using CMake directly:

```bash
# Create build directory
mkdir build
cd build

# Configure for a specific locale (e.g., Japanese)
cmake .. -DLOCALE=ja

# Build
cmake --build .

# Install the library (optional)
sudo cmake --build . --target install
```

_(Alternatively, on Linux/macOS, you can just run `make` and `sudo make install`)_

## Building on Windows

This project can be built on Windows using Visual Studio and CMake. Here's how:

### Prerequisites for Windows

1. **Visual Studio 2022** with C++ development tools
   - Download from https://visualstudio.microsoft.com/
   - Ensure you install the "Desktop development with C++" workload
2. **CMake** 3.10 or higher
   - Download from https://cmake.org/download/
   - Ensure CMake is added to your system PATH during installation
3. **SQLite** pre-compiled binaries and source code
4. **ICU4C** pre-compiled binaries

### Step 1: Download and Extract Dependencies

#### SQLite
1. Download the pre-compiled SQLite binaries:
   - Visit https://www.sqlite.org/download.html
   - Download the "Precompiled Binaries for Windows" (sqlite-dll-win64-x64-*.zip)
   - Extract to a directory of your choice (e.g., `C:\sqlite`)

2. Download the SQLite source code:
   - From the same page, download "Source Code" (sqlite-src-*.zip)
   - Extract to a directory of your choice (e.g., `C:\sqlite-src`)

#### ICU4C
1. Download pre-compiled ICU4C binaries:
   - Visit https://github.com/unicode-org/icu/releases
   - Download the latest Windows binaries (e.g., `icu4c-*-Win64-msvc.zip`)
   - Extract to a directory of your choice (e.g., `C:\icu`)

### Step 2: Generate SQLite Header Files

1. Open "Developer PowerShell for VS 2022" (from Start Menu) - this is the recommended shell
2. Navigate to your SQLite source directory:
   ```powershell
   cd C:\sqlite-src
   ```
3. Generate the sqlite3.h header file:
   ```powershell
   nmake /f Makefile.msc sqlite3.h
   ```
4. Create an include directory in your SQLite binaries folder:
   ```powershell
   mkdir C:\sqlite\include
   ```
5. Copy the generated header files:
   ```powershell
   copy sqlite3.h C:\sqlite\include\sqlite3.h
   copy src\sqlite3ext.h C:\sqlite\include\sqlite3ext.h
   ```

### Step 3: Generate SQLite Import Library

1. In the same PowerShell window, navigate to your SQLite binaries directory:
   ```powershell
   cd C:\sqlite
   ```
2. Generate the import library from the DEF file:
   ```powershell
   lib /def:sqlite3.def /out:sqlite3.lib /machine:x64
   ```

### Step 4: Build the FTS5 ICU Tokenizer

1. Clone or download this repository to a directory of your choice
2. Create a build directory:
   ```powershell
   mkdir build
   cd build
   ```
3. Configure with CMake (replace paths with your actual paths):
   ```powershell
   cmake -G "Visual Studio 17 2022" -T host=x64 -A x64 .. -DICU_ROOT="C:\icu" -DSQLite3_INCLUDE_DIR="C:\sqlite\include" -DSQLite3_LIBRARY="C:\sqlite\sqlite3.lib"
   ```
4. Build the project:
   ```powershell
   cmake --build . --config Release
   ```

To build for a specific locale (e.g., Thai), add the LOCALE parameter during CMake configuration:

```powershell
cmake -G "Visual Studio 17 2022" -T host=x64 -A x64 .. -DICU_ROOT="C:\icu" -DSQLite3_INCLUDE_DIR="C:\sqlite\include" -DSQLite3_LIBRARY="C:\sqlite\sqlite3.lib" -DLOCALE=th
```

This will create `fts5_icu_th.dll` and register the tokenizer as `icu_th`.

### Step 5: Using the Extension

After successful compilation, you'll find `fts5_icu.dll` (or `fts5_icu_xx.dll` for locale-specific builds) in the `build\Release` directory. To use it with SQLite:

#### Method 1: Simple Load (Windows)

The easiest and most reliable method on Windows is to copy the built `fts5_icu_v2.dll` along with `icudt77.dll` and `icuuc77.dll` from the pre-compiled ICU4C (in this case ICU77) to your current directory, then use the command:

```sql
.load fts5_icu.dll

CREATE VIRTUAL TABLE documents USING fts5(
    content,
    tokenize = 'icu'
);
```

This method is recommended over full path loading because of how Windows resolves DLL dependencies. When you use a full path to load the extension (e.g., `.load ./build/Release/fts5_icu.dll`), Windows may not automatically search for the required ICU DLLs (`icudt77.dll` and `icuuc77.dll`) in the same directory. Instead, it follows the Windows DLL search order, which typically looks in:

1. The directory where the application (SQLite) is located
2. The system directory
3. The Windows directory
4. The current directory
5. The directories listed in the PATH environment variable

By copying the DLLs to the current directory and using the simple load command, you ensure that all required DLLs are found correctly.

## Usage (FTS5 v2 - Default and Recommended)

After compiling, you can load the specific tokenizer you built into SQLite.

**Example for the Thai Tokenizer:**

```sql
-- Provide the path to the specific library in your build directory.
.load ./build/libfts5_icu_th.so

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
.load ./build/libfts5_icu.so

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

## Locale Name Mappings

For compatibility with common usage, this project supports alternative locale codes:

1. **Mapped with warnings** (the alias is converted to the standard code):
   - **Chinese**: `cn` → `zh` (with warning)
   - **Japanese**: `jp` → `ja` (with warning)

2. **Direct support** (both codes work without mapping or warnings):
   - **Korean**: `kr` ↔ `ko`
   - **Hebrew**: `iw` ↔ `he`
   - **Greek**: `gr` ↔ `el`

When using the mapped alias codes (`cn` or `jp`), you will see a warning message during the build process informing you of the mapping, but the resulting library will use the standard ICU locale code in its name and functionality.

Examples:
```bash
# This will show a warning and build libfts5_icu_zh.so
cmake .. -DLOCALE=cn

# This will build libfts5_icu_zh.so directly without warning
cmake .. -DLOCALE=zh

# These will both build libfts5_icu_ko.so without any warnings
cmake .. -DLOCALE=kr
cmake .. -DLOCALE=ko
```

## Testing

This project includes comprehensive tests for all supported locales. You can run individual tests or all tests at once:

### Running All Tests

```bash
# Build all tokenizers
./scripts/build_all.sh

# Test all tokenizers
./scripts/test_all.sh
```

### Running Individual Locale Tests

```bash
# Test a specific locale (example with Japanese)
sqlite3 < tests/test_ja_tokenizer.sql

# Test the universal tokenizer
sqlite3 < tests/test_universal_tokenizer.sql
```

### Supported Locales and Test Files

Each supported locale has a corresponding test file in the `tests/` directory:

- **ar** (Arabic): `tests/test_ar_tokenizer.sql`
- **el** (Greek): `tests/test_el_tokenizer.sql`
- **he** (Hebrew): `tests/test_he_tokenizer.sql` (also supports `iw` alias)
- **ja** (Japanese): `tests/test_ja_tokenizer.sql`
- **ko** (Korean): `tests/test_ko_tokenizer.sql` (also supports `kr` alias)
- **ru** (Russian): `tests/test_ru_tokenizer.sql`
- **th** (Thai): `tests/test_th_tokenizer.sql`
- **zh** (Chinese): `tests/test_zh_tokenizer.sql` (also supports `cn` alias)
- **Universal**: `tests/test_universal_tokenizer.sql`

Note: For locales with aliases (`cn`→`zh`, `jp`→`ja`, `kr`→`ko`, `iw`→`he`, `gr`→`el`), the same test file works for both the standard code and its aliases, as they all map to the same tokenizer functionality.

## Testing the ICU Transliterator

This project includes a simple C program to test the enhanced ICU transliterator rules with various language samples.

### Building and Running the Test

You can build and run the test program using the provided scripts:

```bash
# Build and run the test
./scripts/run_test.sh

# Or just build the test
./scripts/build_test.sh
```

The test program demonstrates that the transliterator correctly converts various scripts to Latin/ASCII form, including:
- Arabic
- Cyrillic
- Hebrew
- Greek
- Chinese (both Traditional and Simplified)
- Japanese
- Text with diacritics

The transliterator uses the following rule chain:
`NFKD; Arabic-Latin; Cyrillic-Latin; Hebrew-Latin; Greek-Latin; Latin-ASCII; Lower; NFKC; Traditional-Simplified; Katakana-Hiragana`

This ensures comprehensive script conversion and normalization for effective text search and indexing.

## Locale-Specific Transliterator Rules

For optimized performance with specific languages, see the documentation in [docs/BUILD_TEST_README.md](docs/BUILD_TEST_README.md) for information about locale-specific rules.

The locale-specific tests can be found in the [tests/](tests/) directory.

### Why Locale-Specific Tokenizers Are More Efficient

When you build a tokenizer for a specific locale (e.g., `-DLOCALE=ja` for Japanese), the resulting library uses transliterator rules that are optimized for that language:

1. **Reduced Processing Overhead**: Instead of applying transformations for all possible scripts (Latin, Cyrillic, Arabic, Chinese, etc.), the locale-specific tokenizer only applies the transformations relevant to that language.

2. **Language-Appropriate Normalization**: Each locale uses normalization rules that are appropriate for that language's characteristics:
   - **Japanese** (`ja`): `NFKD; Katakana-Hiragana; Lower; NFKC`
   - **Chinese** (`zh`): `NFKD; Traditional-Simplified; Lower; NFKC`
   - **Thai** (`th`): `NFKD; Lower; NFKC`
   - **Korean** (`ko`): `NFKD; Lower; NFKC`
   - **Arabic** (`ar`): `NFKD; Arabic-Latin; Lower; NFKC`
   - **Russian** (`ru`): `NFKD; Cyrillic-Latin; Lower; NFKC`
   - **Hebrew** (`he`): `NFKD; Hebrew-Latin; Lower; NFKC`
   - **Greek** (`el`): `NFKD; Greek-Latin; Lower; NFKC`

3. **Faster Text Processing**: By eliminating unnecessary script conversions, locale-specific tokenizers can process text significantly faster than the universal tokenizer.

4. **More Accurate Results**: Language-specific rules provide more accurate normalization and transliteration for the target language.

In contrast, the **universal tokenizer** uses a comprehensive rule set that includes transformations for all supported scripts:
`NFKD; Arabic-Latin; Cyrillic-Latin; Hebrew-Latin; Greek-Latin; Latin-ASCII; Lower; NFKC; Traditional-Simplified; Katakana-Hiragana`

While the universal tokenizer can handle text in any supported language, it has higher processing overhead because it must check and potentially apply all transformations for every piece of text.

### When to Use Each Approach

- **Use locale-specific tokenizers** when you know the primary language of your text data and performance is important.
- **Use the universal tokenizer** when dealing with mixed-language content or when the language of the text is unknown at build time.

