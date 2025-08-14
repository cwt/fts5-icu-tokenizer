# Set the minimum required version of CMake
cmake_minimum_required(VERSION 3.10)

# Define the project name, version, and language
project(fts5-icu-tokenizer VERSION 3.0 LANGUAGES C)

# Set the C standard to C11
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# --- Dynamic Locale Configuration ---

# Define a variable for the locale, which can be set from the cmake command line.
# e.g., cmake .. -DLOCALE=th
# Defaults to "" for a generic, universal word breaker.
set(LOCALE "" CACHE STRING "The locale for the ICU tokenizer (e.g., th, cn, ja)")

# Construct the library suffix and tokenizer name based on the LOCALE variable.
if(LOCALE)
  set(LIB_SUFFIX "_${LOCALE}")
  set(TOKENIZER_NAME "icu_${LOCALE}")
  # Sanitize the locale for the C function name, replacing hyphens with underscores.
  string(REPLACE "-" "_" C_INIT_SUFFIX "${LOCALE}")
else()
  set(LIB_SUFFIX "")
  set(TOKENIZER_NAME "icu")
  set(C_INIT_SUFFIX "") # Pass an empty suffix for the default case
endif()

message(STATUS "Building tokenizer for locale: '${LOCALE}'")
message(STATUS "Library name will be: fts5_icu${LIB_SUFFIX}")
message(STATUS "Registered FTS5 tokenizer name will be: '${TOKENIZER_NAME}'")


# --- Find Dependencies ---

# Find the ICU library, requiring the internationalization (i18n) and
# common utilities (uc) components.
find_package(ICU REQUIRED COMPONENTS i18n uc)

# Find the SQLite3 library.
find_package(SQLite3 REQUIRED)

# --- Configure the Library ---

# Add the source file to a variable for clarity.
set(SOURCES src/fts5_icu.c)

# Create the shared library from the source file.
add_library(fts5_icu SHARED ${SOURCES})

# Set the dynamic output name for the library file.
set_target_properties(fts5_icu PROPERTIES OUTPUT_NAME "fts5_icu${LIB_SUFFIX}")

# Pass the locale, tokenizer name, and init function suffix to the C code.
# The escaped quotes are important for passing string values.
# The INIT_LOCALE_SUFFIX does not have quotes so it can be used for token pasting.
target_compile_definitions(fts5_icu PRIVATE
  "TOKENIZER_LOCALE=\"${LOCALE}\""
  "TOKENIZER_NAME=\"${TOKENIZER_NAME}\""
  "INIT_LOCALE_SUFFIX=${C_INIT_SUFFIX}"
)

# Link the library against the libraries found by CMake.
# This adds the necessary include directories and linker flags.
target_link_libraries(fts5_icu PRIVATE ICU::i18n ICU::uc SQLite::SQLite3)

# On Windows, we need to define SQLITE_ENABLE_FTS5
if(WIN32)
  target_compile_definitions(fts5_icu PRIVATE SQLITE_ENABLE_FTS5)
endif()


# --- Installation ---

# Define where to install the compiled library.
# This uses standard GNU locations. On Linux, this will typically be /usr/local/lib.
include(GNUInstallDirs)
install(TARGETS fts5_icu
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})

# Print a message showing the install location after the build.
message(STATUS "Install directory: ${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}")
