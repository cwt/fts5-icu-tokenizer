const std = @import("std");
const rules = @import("rules.zig");
const tokenizer = @import("tokenizer.zig");

fn testTransliterator(gpa: std.mem.Allocator, input: []const u8, testName: []const u8) !void {
    const output = try tokenizer.transliterateString(gpa, input, rules.ICU_RULE_DEFAULT);
    defer gpa.free(output);

    std.debug.print("=== {s} ===\n", .{testName});
    std.debug.print("Input:  {s}\n", .{input});
    std.debug.print("Output: {s}\n\n", .{output});
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    std.debug.print("ICU Transliterator Test Program (Zig)\n", .{});
    std.debug.print("===================================\n\n", .{});

    try testTransliterator(gpa, "العربية", "Arabic");
    try testTransliterator(gpa, "русский", "Cyrillic");
    try testTransliterator(gpa, "עברית", "Hebrew");
    try testTransliterator(gpa, "Ελληνικά", "Greek");
    try testTransliterator(gpa, "中文", "Chinese");
    try testTransliterator(gpa, "日本語", "Japanese");
    try testTransliterator(gpa, "Français", "French with diacritics");
    try testTransliterator(gpa, "Español", "Spanish with diacritics");
    try testTransliterator(gpa, "ỆᶍǍᶆṔƚÉ", "Complex diacritics");

    try testTransliterator(gpa, "Τη γλώσσα μου έδωσαν ελληνικό", "Greek phrase");
    try testTransliterator(gpa, "В чащах юга жил бы цитрус? Да, но фальшивый экземпляр!", "Russian phrase");
    try testTransliterator(gpa, "視野無限廣，窗外有藍天", "Traditional Chinese");
    try testTransliterator(gpa, "视野无限广，窗外有蓝天", "Simplified Chinese");

    std.debug.print("All tests completed successfully.\n", .{});
}
