const std = @import("std");
const c = @import("c");
const icu = @import("c_icu");
const tokenizer = @import("tokenizer.zig");

fn testTransliteratorWithRules(gpa: std.mem.Allocator, input: []const u8, rule_str: []const u8, testName: []const u8) !void {
    var status: c.UErrorCode = c.U_ZERO_ERROR;

    const rules_u16 = try tokenizer.utf8ToUtf16Alloc(gpa, rule_str);
    defer gpa.free(rules_u16);

    const transliterator = icu.utrans_openU(rules_u16.ptr, -1, c.UTRANS_FORWARD, null, 0, null, &status);
    if (c.U_FAILURE(status) or transliterator == null) {
        std.debug.print("Error creating transliterator with rules '{s}'\n", .{rule_str});
        return error.TransliteratorCreateFailed;
    }
    defer icu.utrans_close(transliterator);

    const input_u16 = try tokenizer.utf8ToUtf16Alloc(gpa, input);
    defer gpa.free(input_u16);

    const capacity = input_u16.len * 3 + 64;
    const output_u16 = try gpa.alloc(c.UChar, capacity);
    defer gpa.free(output_u16);

    @memcpy(output_u16[0..input_u16.len], input_u16);

    var limit: i32 = @intCast(input_u16.len);
    var out_len: i32 = @intCast(input_u16.len);
    status = c.U_ZERO_ERROR;
    icu.utrans_transUChars(transliterator, output_u16.ptr, &out_len, @intCast(capacity), 0, &limit, &status);
    if (c.U_FAILURE(status)) {
        return error.TransliterateFailed;
    }

    var utf8_len: i32 = 0;
    status = c.U_ZERO_ERROR;
    _ = icu.u_strToUTF8(null, 0, &utf8_len, output_u16.ptr, limit, &status);
    if (status != c.U_BUFFER_OVERFLOW_ERROR and status != c.U_ZERO_ERROR) {
        return error.Utf8LengthFailed;
    }

    status = c.U_ZERO_ERROR;
    const utf8_output = try gpa.alloc(u8, @intCast(utf8_len + 1));
    defer gpa.free(utf8_output);

    _ = icu.u_strToUTF8(utf8_output.ptr, utf8_len + 1, null, output_u16.ptr, limit, &status);
    if (c.U_FAILURE(status)) {
        return error.Utf8ConvertFailed;
    }

    std.debug.print("=== {s} ===\n", .{testName});
    std.debug.print("Rules:  {s}\n", .{rule_str});
    std.debug.print("Input:  {s}\n", .{input});
    std.debug.print("Output: {s}\n\n", .{utf8_output[0..@intCast(utf8_len)]});
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    std.debug.print("Locale-Specific ICU Transliterator Test Program (Zig)\n", .{});
    std.debug.print("===================================================\n\n", .{});

    try testTransliteratorWithRules(gpa, "中文", "NFKD; Traditional-Simplified; Lower; NFKC", "Chinese (zh)");
    try testTransliteratorWithRules(gpa, "日本語", "NFKD; Katakana-Hiragana; Lower; NFKC", "Japanese (ja)");
    try testTransliteratorWithRules(gpa, "ภาษาไทย", "NFKD; Lower; NFKC", "Thai (th)");
    try testTransliteratorWithRules(gpa, "한국어", "NFKD; Lower; NFKC", "Korean (ko)");
    try testTransliteratorWithRules(gpa, "العربية", "NFKD; Arabic-Latin; Lower; NFKC", "Arabic (ar)");
    try testTransliteratorWithRules(gpa, "русский", "NFKD; Cyrillic-Latin; Lower; NFKC", "Russian (ru)");
    try testTransliteratorWithRules(gpa, "עברית", "NFKD; Hebrew-Latin; Lower; NFKC", "Hebrew (he)");
    try testTransliteratorWithRules(gpa, "Ελληνικά", "NFKD; Greek-Latin; Lower; NFKC", "Greek (el)");
    try testTransliteratorWithRules(gpa, "Français", "NFKD; Latin-ASCII; Lower; NFKC", "French (fr)");

    std.debug.print("All locale-specific tests completed.\n", .{});
}
