const std = @import("std");
const tokenizer = @import("tokenizer.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    std.debug.print("Testing locale-specific ICU transliterator rules (Zig)\n", .{});
    std.debug.print("=====================================================\n\n", .{});

    const rule_str = "NFKD; Traditional-Simplified; Lower";
    const input = "繁體中文測試";
    std.debug.print("Input: {s}\n", .{input});

    const output = try tokenizer.transliterateString(gpa, input, rule_str);
    defer gpa.free(output);

    std.debug.print("Output: {s}\n\n", .{output});
    std.debug.print("Test completed successfully!\n", .{});
}
