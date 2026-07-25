const std = @import("std");
const c = @import("c");
const tokenizer = @import("tokenizer.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    std.debug.print("Testing locale-specific ICU transliterator rules (Zig)\n", .{});
    std.debug.print("=====================================================\n\n", .{});

    var status: c.UErrorCode = c.U_ZERO_ERROR;
    const rule_str = "NFKD; Traditional-Simplified; Lower";
    const rules_u16 = try tokenizer.utf8ToUtf16Alloc(gpa, rule_str);
    defer gpa.free(rules_u16);

    const transliterator = c.utrans_openU(rules_u16.ptr, -1, c.UTRANS_FORWARD, null, 0, null, &status);
    if (c.U_FAILURE(status) or transliterator == null) {
        std.debug.print("Error creating Chinese transliterator\n", .{});
        return error.TransliteratorCreateFailed;
    }
    defer c.utrans_close(transliterator);

    const input = "繁體中文測試";
    std.debug.print("Input: {s}\n", .{input});

    const input_u16 = try tokenizer.utf8ToUtf16Alloc(gpa, input);
    defer gpa.free(input_u16);

    const capacity = input_u16.len * 3 + 64;
    const output_u16 = try gpa.alloc(c.UChar, capacity);
    defer gpa.free(output_u16);

    @memcpy(output_u16[0..input_u16.len], input_u16);

    var limit: i32 = @intCast(input_u16.len);
    var out_len: i32 = @intCast(input_u16.len);
    status = c.U_ZERO_ERROR;
    c.utrans_transUChars(transliterator, output_u16.ptr, &out_len, @intCast(capacity), 0, &limit, &status);
    if (c.U_FAILURE(status)) {
        return error.TransliterateFailed;
    }

    var utf8_len: i32 = 0;
    status = c.U_ZERO_ERROR;
    _ = c.u_strToUTF8(null, 0, &utf8_len, output_u16.ptr, limit, &status);
    if (status != c.U_BUFFER_OVERFLOW_ERROR and status != c.U_ZERO_ERROR) {
        return error.Utf8LengthFailed;
    }

    status = c.U_ZERO_ERROR;
    const utf8_output = try gpa.alloc(u8, @intCast(utf8_len + 1));
    defer gpa.free(utf8_output);

    _ = c.u_strToUTF8(utf8_output.ptr, utf8_len + 1, null, output_u16.ptr, limit, &status);
    if (c.U_FAILURE(status)) {
        return error.Utf8ConvertFailed;
    }

    std.debug.print("Output: {s}\n\n", .{utf8_output[0..@intCast(utf8_len)]});
    std.debug.print("Test completed successfully!\n", .{});
}
