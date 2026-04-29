# FTS5 ICU Tokenizer for SQLite

This project provides custom FTS5 tokenizers for SQLite that use the International Components for Unicode (ICU) library to provide robust word segmentation for various languages.

The project supports both FTS5 API v1 (legacy) and API v2 (current) implementations, with the ability to build either version based on your needs. The target locale is configurable at build time, with support for both universal and locale-specific tokenizers.

- **API v2**: Current implementation with full FTS5 capabilities and enhanced features (default)
- **API v1**: Legacy implementation for older SQLite versions without FTS5 API v2 support
- **Both**: Written in C for maximum stability and performance in high-availability systems

---

## Quick Start

### Prerequisites
- **CMake** (version 3.10 or higher)
- **C Compiler** (GCC, Clang, or MSVC)
- **SQLite3** development libraries

| Platform | Install |
|----------|---------|
| Debian/Ubuntu | `apt install cmake libsqlite3-dev libicu-dev` |
| RHEL/Fedora | `dnf install cmake sqlite-devel libicu-devel` |
| macOS (Homebrew) | `brew install cmake sqlite icu4c` |
| Windows | See [Windows Build](#windows-build) below |

### RHEL Compatibility Note
For RHEL-based distributions (RHEL, CentOS, Rocky Linux, AlmaLinux, etc.) and other systems with older SQLite versions, use the legacy API v1 as detailed below.

---

## Building & Testing (API v2 - Default)

```bash
# Build all tokenizers (API v2 by default)
./scripts/build_all.sh

# Test all tokenizers
./scripts/test_all.sh
```

## Building & Testing (API v1 - Legacy)

For older SQLite versions that don't support FTS5 API v2:

```bash
# Build all legacy API v1 tokenizers
./scripts/build_all_legacy.sh

# Test all legacy API v1 tokenizers
./scripts/test_all_legacy.sh

# Build all tokenizers for both API versions
./scripts/build_all_with_legacy.sh
```

---

## Building Individual Locales

### API v2 (Default)
```bash
mkdir build && cd build
cmake .. -DLOCALE=ja  # e.g., Japanese
make
```

> **macOS**: Homebrew installs `icu4c` and `sqlite` as keg-only (not in standard paths). The build scripts handle this automatically. For manual cmake, add:
> ```bash
> ICU_PREFIX=$(brew --prefix icu4c)
> cmake .. -DLOCALE=ja \
>   -DICU_ROOT="$ICU_PREFIX" -DICU_INCLUDE_DIR="$ICU_PREFIX/include" \
>   -DSQLite3_ROOT=$(brew --prefix sqlite)
> ```

### API v1 (Legacy - for RHEL & older SQLite)
```bash
mkdir build && cd build
cmake .. -DAPI_VERSION=v1 -DLOCALE=ja  # e.g., Japanese
make
```

The resulting library will have a `_legacy` suffix (e.g., `libfts5_icu_ja_legacy.so`).

---

## Usage Examples

### Loading API v1 (Legacy) Tokenizers
```sql
.load ./build/libfts5_icu_th_legacy  -- Extension (.so/.dll) is optional and best omitted for portability

CREATE VIRTUAL TABLE documents_th USING fts5(
    content,
    tokenize = 'icu_th'
);
```

### Loading API v2 (Current) Tokenizers
```sql
.load ./build/libfts5_icu_th

CREATE VIRTUAL TABLE documents_th USING fts5(
    content,
    tokenize = 'icu_th'
);
```

### Example: Thai Text Search
```sql
-- Load the appropriate library
.load ./build/libfts5_icu_th

-- Create table and search
CREATE VIRTUAL TABLE documents_th USING fts5(content, tokenize = 'icu_th');
INSERT INTO documents_th(content) VALUES ('การทดสอบภาษาไทยในระบบค้นหา');
SELECT * FROM documents_th WHERE documents_th MATCH 'ภาษา';
```

### Example: Universal Multi-Language Support
```sql
.load ./build/libfts5_icu

CREATE VIRTUAL TABLE documents USING fts5(content, tokenize = 'icu');
INSERT INTO documents(content) VALUES ('甜蜜蜜,你笑得甜蜜蜜-หวานปานน้ำผึ้ง,ยิ้มของคุณช่างหวานปานน้ำผึ้ง');
SELECT * FROM documents WHERE documents MATCH 'หวาน';
```

---

## Supported Locales

| Locale | Language | Test File |
|--------|----------|-----------|
| `ar` | Arabic | `tests/test_ar_tokenizer.sql` |
| `el` | Greek | `tests/test_el_tokenizer.sql` |
| `he` | Hebrew | `tests/test_he_tokenizer.sql` |
| `ja` | Japanese | `tests/test_ja_tokenizer.sql` |
| `ko` | Korean | `tests/test_ko_tokenizer.sql` |
| `ru` | Russian | `tests/test_ru_tokenizer.sql` |
| `th` | Thai | `tests/test_th_tokenizer.sql` |
| `zh` | Chinese | `tests/test_zh_tokenizer.sql` |
| - | Universal | `tests/test_universal_tokenizer.sql` |

### Locale Mappings
- `cn` → `zh` (Chinese, with warning)
- `jp` → `ja` (Japanese, with warning)
- `kr` ↔ `ko` (Korean, both supported)
- `iw` ↔ `he` (Hebrew, both supported)
- `gr` ↔ `el` (Greek, both supported)

---

## Advanced Configuration

### Windows Build
For Windows using Visual Studio:

```powershell
mkdir build
cd build
cmake -G "Visual Studio 17 2022" -T host=x64 -A x64 .. -DICU_ROOT="C:\icu" -DSQLite3_INCLUDE_DIR="C:\sqlite\include" -DSQLite3_LIBRARY="C:\sqlite\sqlite3.lib" -DAPI_VERSION=v1 -DLOCALE=th
cmake --build . --config Release
```

### Locale-Specific Performance Optimizations
Locale-specific tokenizers use optimized ICU rules for each language:

- **Japanese** (`ja`): `NFKD; Katakana-Hiragana; Lower; NFKC`
- **Chinese** (`zh`): `NFKD; Traditional-Simplified; Lower; NFKC`
- **Thai** (`th`): `NFKD; Lower; NFKC`
- **Korean** (`ko`): `NFKD; Lower; NFKC`
- **Arabic** (`ar`): `NFKD; Arabic-Latin; Lower; NFKC`
- **Russian** (`ru`): `NFKD; Cyrillic-Latin; Lower; NFKC`
- **Hebrew** (`he`): `NFKD; Hebrew-Latin; Lower; NFKC`
- **Greek** (`el`): `NFKD; Greek-Latin; Lower; NFKC`

**Universal tokenizer** rule: `NFKD; Arabic-Latin; Cyrillic-Latin; Hebrew-Latin; Greek-Latin; Latin-ASCII; Lower; NFKC; Traditional-Simplified; Katakana-Hiragana`

### When to Use Each Approach
- **Locale-specific**: When you know the primary language and performance is important
- **Universal**: For mixed-language content or unknown language at build time

---

## Code Quality & Maintenance

### Formatting & Linting
```bash
# Format all source files
./scripts/code-format.sh

# Run static analysis
./scripts/lint-check.sh
```

### Documentation
- [Script Reference](docs/SCRIPTS_REFERENCE.md) - Complete list of available scripts
- [Build & Test Guide](docs/BUILD_TEST_README.md) - Detailed building and testing information
- [API Implementation Details](docs/FTS5_API_IMPLEMENTATION.md) - Technical implementation documentation

---

## Key Benefits

- **High-Performance Text Search**: Optimized for various languages using ICU
- **Cross-Platform Compatibility**: Works on Linux, Windows, and macOS
- **RHEL Support**: Backwards compatibility for older SQLite versions
- **Robust UTF-8 handling**: Correctly processes Unicode replacement characters (U+FFFD) and handles invalid sequences safely
- **Memory Safe**: Includes buffer overflow prevention and defense-in-depth security checks
- **Modular Design**: Clean, well-documented code structure