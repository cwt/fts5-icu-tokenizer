const std = @import("std");
const rules = @import("rules.zig");
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

    try testTransliteratorWithRules(gpa, "中文", rules.ICU_RULE_ZH, "Chinese (zh)");
    try testTransliteratorWithRules(gpa, "日本語", rules.ICU_RULE_JA, "Japanese (ja)");
    try testTransliteratorWithRules(gpa, "ภาษาไทย", rules.ICU_RULE_TH, "Thai (th)");
    try testTransliteratorWithRules(gpa, "한국어", rules.ICU_RULE_KO, "Korean (ko)");
    try testTransliteratorWithRules(gpa, "العربية", rules.ICU_RULE_AR, "Arabic (ar)");
    try testTransliteratorWithRules(gpa, "русский", rules.ICU_RULE_RU, "Russian (ru)");
    try testTransliteratorWithRules(gpa, "עברית", rules.ICU_RULE_HE, "Hebrew (he)");
    try testTransliteratorWithRules(gpa, "Ελληνικά", rules.ICU_RULE_EL, "Greek (el)");
    try testTransliteratorWithRules(gpa, "Français", rules.ICU_RULE_BASE ++ rules.ICU_RULE_LATIN_NORMALIZE ++ "NFKC", "French (fr)");

    std.debug.print("All locale-specific tests completed.\n", .{});
}
