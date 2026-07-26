const std = @import("std");
const tokenizer = @import("tokenizer.zig");

fn testTransliteratorWithRules(gpa: std.mem.Allocator, input: []const u8, rule_str: []const u8, testName: []const u8) !void {
    const output = try tokenizer.transliterateString(gpa, input, rule_str);
    defer gpa.free(output);

    std.debug.print("=== {s} ===\n", .{testName});
    std.debug.print("Rules:  {s}\n", .{rule_str});
    std.debug.print("Input:  {s}\n", .{input});
    std.debug.print("Output: {s}\n\n", .{output});
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
