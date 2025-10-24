# Contribution Guide for FTS5 ICU Tokenizer

## Code Style and Readability Standards

This project follows specific standards to maintain code readability for all contributors. Please follow these guidelines when making changes.

## Function Design

- **Single Responsibility**: Each function should perform one, clearly defined task
- **Maximum Length**: Keep functions under 50 lines when possible
- **Clear Naming**: Use descriptive names that explain the function's purpose
- **Documentation**: All non-trivial functions should have doxygen-style comments

## Variable Naming

- Use descriptive names that indicate the variable's purpose
- Prefer `utf16_text_buffer` over `pUText`
- Use `position_counter` instead of `iPos`
- Be consistent with naming patterns used elsewhere in the codebase

## Documentation Standards

Every non-trivial function must include a doxygen-style comment block:

```c
/**
 * @brief Brief description of what the function does
 * 
 * More detailed explanation of the function's behavior,
 * parameters, return values, and any important notes.
 * 
 * @param param1 Description of the first parameter
 * @param param2 Description of the second parameter
 * @return Description of the return value
 */
static int example_function(int param1, char* param2) {
    // Function implementation
}
```

## Code Organization

- Group related functions together
- Use clear section headers with consistent formatting:
  ```
  // ========================================================================
  // === SECTION HEADER =====================================================
  // ========================================================================
  ```
- Place helper functions near the functions that use them
- Keep related data structures and functions together

## Error Handling

- Check for buffer overflows and integer overflows
- Provide clear error codes for debugging
- Clean up allocated memory in all error paths
- Use consistent error handling patterns

## Memory Management

- Always check return values from memory allocation functions
- Free all allocated memory in error paths and success paths
- Use appropriate buffer sizes with safety margins
- Document the purpose of each buffer allocation

## ICU Library Usage

- Include appropriate error status checks after ICU operations
- Handle ICU-specific edge cases (like invalid Unicode sequences)
- Document ICU rule selection rationale
- Follow ICU best practices for resource management

## Testing

- New functionality should include appropriate tests
- Changes to existing functionality should not break existing tests
- Test edge cases thoroughly, especially with different Unicode inputs
- Ensure all locale-specific functionality is properly tested

## Commit Messages

- Use present tense: "Fix buffer overflow" not "Fixed buffer overflow"
- Be descriptive but concise
- Reference issue numbers where appropriate
- Describe the "why" as well as the "what" when needed

## Pull Request Process

1. Follow all code standards in this guide
2. Update documentation if your changes affect the public API
3. Include tests for new functionality
4. Ensure all existing tests pass
5. Provide a clear description of your changes and their purpose
6. Request code review from other maintainers

## Maintaining Readability

Remember that code is read many more times than it is written. When making changes:

- Consider how new developers will understand your code
- Add comments for complex algorithms or non-obvious decisions
- Refactor existing code if you notice opportunities for improvement
- Follow the existing code style and patterns
- Keep the code self-documenting through clear names and structure