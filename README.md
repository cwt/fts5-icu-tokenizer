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
   cmake -G "Visual Studio 17 2022" -T host=x64 -A x64 .. `
     -DICU_ROOT="C:\icu" `
     -DSQLite3_INCLUDE_DIR="C:\sqlite\include" `
     -DSQLite3_LIBRARY="C:\sqlite\sqlite3.lib"
   ```
4. Build the project:
   ```powershell
   cmake --build . --config Release
   ```

### Step 5: Using the Extension

After successful compilation, you'll find `fts5_icu.dll` in the `build\Release` directory. To use it with SQLite:

#### Method 1: Simple Load (Windows)

The easiest and most reliable method on Windows is to copy the built `fts5_icu.dll` along with `icudt77.dll` and `icuuc77.dll` from the pre-compiled ICU4C (in this case ICU77) to your current directory, then use the command:

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

#### Method 2: Full Path Load (Not Recommended on Windows)

Alternatively, you can load the extension using the full path, but this may cause issues with loading the required ICU DLLs:

```sql
.load ./build/Release/fts5_icu.dll

CREATE VIRTUAL TABLE documents USING fts5(
    content,
    tokenize = 'icu'
);
```

To build for a specific locale (e.g., Thai), add the LOCALE parameter during CMake configuration:

```powershell
cmake -G "Visual Studio 17 2022" -T host=x64 -A x64 .. `
  -DICU_ROOT="C:\icu" `
  -DSQLite3_INCLUDE_DIR="C:\sqlite\include" `
  -DSQLite3_LIBRARY="C:\sqlite\sqlite3.lib" `
  -DLOCALE=th
```

This will create `fts5_icu_th.dll` and register the tokenizer as `icu_th`.

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
