# Set the minimum required version of CMake
cmake_minimum_required(VERSION 3.10)

# Define the project name, version, and language
project(fts5-icu-tokenizer VERSION 4.0 LANGUAGES C)

# Set policy to allow using _ROOT variables
if(POLICY CMP0074)
  cmake_policy(SET CMP0074 NEW)
endif()

# Set the C standard to C11
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# --- Dynamic Locale Configuration ---

# Define a variable for the locale, which can be set from the cmake command line.
# e.g., cmake .. -DLOCALE=th
# Defaults to "" for a generic, universal word breaker.
set(LOCALE "" CACHE STRING "The locale for the ICU tokenizer (e.g., th, cn, ja)")

# Handle special case for Chinese and Japanese locales
if(LOCALE STREQUAL "cn")
  message(WARNING "Chinese locale 'cn' is being mapped to 'zh' for ICU compatibility")
  set(LOCALE "zh")
elseif(LOCALE STREQUAL "jp")
  message(WARNING "Japanese locale 'jp' is being mapped to 'ja' for ICU compatibility")
  set(LOCALE "ja")
endif()

# Construct the library suffix and tokenizer name based on the LOCALE variable.
if(LOCALE)
  set(LIB_SUFFIX "_${LOCALE}")
  set(TOKENIZER_NAME "icu_${LOCALE}")
  # Sanitize the locale for the C function name, replacing hyphens with underscores.
  # For the function name, we don't want the leading underscore
  string(REPLACE "-" "_" C_INIT_SUFFIX_NO_UNDERSCORE "${LOCALE}")
  set(C_INIT_SUFFIX "_${C_INIT_SUFFIX_NO_UNDERSCORE}")
else()
  set(LIB_SUFFIX "")
  set(TOKENIZER_NAME "icu")
  set(C_INIT_SUFFIX "") # Pass an empty suffix for the default case
  set(C_INIT_SUFFIX_NO_UNDERSCORE "") # Pass an empty suffix for the default case
endif()

message(STATUS "Building tokenizer for locale: '${LOCALE}'")
message(STATUS "Library name will be: fts5_icu${LIB_SUFFIX}")
message(STATUS "Registered FTS5 tokenizer name will be: '${TOKENIZER_NAME}'")

# Store locale-specific definitions to be applied after target creation
if(LOCALE STREQUAL "ja" OR LOCALE STREQUAL "jp")
  set(LOCALE_DEFINITIONS TOKENIZER_LOCALE_JA)
  set(FUNCTION_SUFFIX _ja)
elseif(LOCALE STREQUAL "zh")
  set(LOCALE_DEFINITIONS TOKENIZER_LOCALE_ZH)
  set(FUNCTION_SUFFIX _zh)
elseif(LOCALE STREQUAL "cn")
  # For 'cn', we still want the Chinese rules but with 'cn' function name
  set(LOCALE_DEFINITIONS TOKENIZER_LOCALE_ZH)
  set(FUNCTION_SUFFIX _cn)
elseif(LOCALE STREQUAL "th")
  set(LOCALE_DEFINITIONS TOKENIZER_LOCALE_TH)
  set(FUNCTION_SUFFIX _th)
elseif(LOCALE STREQUAL "ko" OR LOCALE STREQUAL "kr")
  set(LOCALE_DEFINITIONS TOKENIZER_LOCALE_KO)
  set(FUNCTION_SUFFIX _ko)
elseif(LOCALE STREQUAL "ar")
  set(LOCALE_DEFINITIONS TOKENIZER_LOCALE_AR)
  set(FUNCTION_SUFFIX _ar)
elseif(LOCALE STREQUAL "ru")
  set(LOCALE_DEFINITIONS TOKENIZER_LOCALE_RU)
  set(FUNCTION_SUFFIX _ru)
elseif(LOCALE STREQUAL "he" OR LOCALE STREQUAL "iw")
  set(LOCALE_DEFINITIONS TOKENIZER_LOCALE_HE)
  set(FUNCTION_SUFFIX _he)
elseif(LOCALE STREQUAL "el" OR LOCALE STREQUAL "gr")
  set(LOCALE_DEFINITIONS TOKENIZER_LOCALE_EL)
  set(FUNCTION_SUFFIX _el)
endif()

# --- Find Dependencies ---

# Find the ICU library, requiring the internationalization (i18n) and
# common utilities (uc) components.
find_package(ICU REQUIRED COMPONENTS i18n uc)

# Find the SQLite3 library.
if(WIN32)
  # On Windows, we might need to specify SQLite3 paths explicitly
  if(DEFINED SQLite3_INCLUDE_DIR AND DEFINED SQLite3_LIBRARY)
    # Use the explicitly provided paths
    set(SQLite3_FOUND TRUE)
  else()
    # Try to find SQLite3 using default mechanisms
    find_package(SQLite3)
  endif()
else()
  find_package(SQLite3 REQUIRED)
endif()

# If SQLite3 wasn't found, provide better error message on Windows
if(NOT SQLite3_FOUND)
  if(WIN32)
    message(FATAL_ERROR "SQLite3 not found. Please specify paths using -DSQLite3_INCLUDE_DIR=... and -DSQLite3_LIBRARY=...")
  else()
    message(FATAL_ERROR "SQLite3 not found")
  endif()
endif()

# --- Configure the Library ---

# Create the shared library from the source file.
add_library(fts5_icu SHARED src/fts5_icu.c)

# Set the dynamic output name for the library file.
set_target_properties(fts5_icu PROPERTIES OUTPUT_NAME "fts5_icu${LIB_SUFFIX}")

# Pass the locale, tokenizer name, and init function suffix to the C code.
# The escaped quotes are important for passing string values.
# The INIT_LOCALE_SUFFIX does not have quotes so it can be used for token pasting.
target_compile_definitions(fts5_icu PRIVATE
  "TOKENIZER_LOCALE=\"${LOCALE}\""
  "TOKENIZER_NAME=\"${TOKENIZER_NAME}\""
  "INIT_LOCALE_SUFFIX=${C_INIT_SUFFIX}"
  "C_INIT_SUFFIX_NO_UNDERSCORE=${C_INIT_SUFFIX_NO_UNDERSCORE}"
)

# Define locale-specific macros for compile-time selection
if(LOCALE STREQUAL "ja" OR LOCALE STREQUAL "jp")
  target_compile_definitions(fts5_icu PRIVATE TOKENIZER_LOCALE_JA)
elseif(LOCALE STREQUAL "zh" OR LOCALE STREQUAL "cn")
  target_compile_definitions(fts5_icu PRIVATE TOKENIZER_LOCALE_ZH)
elseif(LOCALE STREQUAL "th")
  target_compile_definitions(fts5_icu PRIVATE TOKENIZER_LOCALE_TH)
elseif(LOCALE STREQUAL "ko" OR LOCALE STREQUAL "kr")
  target_compile_definitions(fts5_icu PRIVATE TOKENIZER_LOCALE_KO)
elseif(LOCALE STREQUAL "ar")
  target_compile_definitions(fts5_icu PRIVATE TOKENIZER_LOCALE_AR)
elseif(LOCALE STREQUAL "ru")
  target_compile_definitions(fts5_icu PRIVATE TOKENIZER_LOCALE_RU)
elseif(LOCALE STREQUAL "he" OR LOCALE STREQUAL "iw")
  target_compile_definitions(fts5_icu PRIVATE TOKENIZER_LOCALE_HE)
elseif(LOCALE STREQUAL "el" OR LOCALE STREQUAL "gr")
  target_compile_definitions(fts5_icu PRIVATE TOKENIZER_LOCALE_EL)
endif()

# Link the library against the libraries found by CMake.
# This adds the necessary include directories and linker flags.
if(WIN32 AND DEFINED SQLite3_INCLUDE_DIR AND DEFINED SQLite3_LIBRARY)
  # Create an imported target for SQLite3 on Windows
  add_library(SQLite3::SQLite3 UNKNOWN IMPORTED)
  set_target_properties(SQLite3::SQLite3 PROPERTIES
    IMPORTED_LOCATION "${SQLite3_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${SQLite3_INCLUDE_DIR}"
  )
  target_link_libraries(fts5_icu PRIVATE ICU::i18n ICU::uc SQLite3::SQLite3)
else()
  target_link_libraries(fts5_icu PRIVATE ICU::i18n ICU::uc SQLite::SQLite3)
endif()

# On Windows, we need to define SQLITE_ENABLE_FTS5
if(WIN32)
  target_compile_definitions(fts5_icu PRIVATE SQLITE_ENABLE_FTS5)
endif()


# --- Test Programs ---

# Add test programs
add_executable(test_transliterator src/test_transliterator.c)
target_link_libraries(test_transliterator PRIVATE ICU::i18n ICU::uc)

add_executable(locale_specific_tests src/locale_specific_tests.c)
target_link_libraries(locale_specific_tests PRIVATE ICU::i18n ICU::uc)

add_executable(test_locale_tokenizer src/test_locale_tokenizer.c)
target_link_libraries(test_locale_tokenizer PRIVATE ICU::i18n ICU::uc SQLite::SQLite3)
target_compile_definitions(test_locale_tokenizer PRIVATE SQLITE_ENABLE_FTS5)

# --- Installation ---

# Define where to install the compiled library.
# This uses standard GNU locations. On Linux, this will typically be /usr/local/lib.
include(GNUInstallDirs)
install(TARGETS fts5_icu
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})

# Print a message showing the install location after the build.
message(STATUS "Install directory: ${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}")
