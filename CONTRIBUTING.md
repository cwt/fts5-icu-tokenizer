# Contribution Guide for FTS5 ICU Tokenizer (Zig 0.16.0)

This project is written in **Zig 0.16.0**. Please follow these guidelines when contributing to maintain codebase quality, memory safety, and consistency.

---

## Code Style & Formatting

- **Standard Tooling**: Always format your code using `zig fmt`. Run `./scripts/code-format.sh` or `zig fmt .` before submitting changes.
- **Static Analysis**: Verify your Zig code with `./scripts/lint-check.sh` (`zig ast-check`).
- **Naming Conventions**:
  - Functions: `camelCase` (e.g., `icuCreate`, `tokenizeText`)
  - Types / Structs: `PascalCase` (e.g., `Fts5Tokenizer`, `TokenizerConfig`)
  - Variables / Parameters: `snake_case` (e.g., `utf8_buffer`, `position_counter`)
  - Constants: `SCREAMING_SNAKE_CASE` or `PascalCase` as appropriate in Zig idioms.

---

## Memory Safety & Allocators

- **Explicit Allocations**: Always pass `std.mem.Allocator` explicitly to functions that allocate heap memory.
- **Deterministic Cleanup**: Use `defer` and `errdefer` semantics to guarantee that every heap allocation (`allocator.alloc`, `allocator.create`) and ICU handle (`ubrk_close`, `utrans_close`) is freed on both normal exit and error paths.
- **Zero Memory Leaks**: Verify that all error paths in tokenizers clean up temporary UTF-8/UTF-16 buffers and ICU handles without leaking memory.

---

## Documentation Standards

- Use Zig doc comments (`///`) directly preceding exported functions, structs, and public types:

```zig
/// Tokenizes the input UTF-8 text using the configured ICU break iterator
/// and transliterator rules.
pub fn tokenizeText(
    self: *Tokenizer,
    text: []const u8,
) !usize {
    // ...
}
```

---

## Testing Guidelines

- **Zig Unit & Integration Tests**: Run `zig build test`, `zig build run-transliterator`, and `zig build run-locale-tests`.
- **SQLite SQL Integration Tests**: Run `./scripts/test.sh` and `./scripts/test_all.sh`.
- **Unicode Coverage**: Ensure new locale tokenizers or transliterators include test cases covering accented characters, complex scripts, and edge cases.

---

## Pull Request Checklist

1. Format code with `zig fmt .` (`./scripts/code-format.sh`).
2. Verify AST check with `./scripts/lint-check.sh`.
3. Run all tests via `./scripts/test_all.sh` and `zig build test`.
4. Provide a clear commit message in present tense describing the "why" and "what" of your change.