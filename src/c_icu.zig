const std = @import("std");
const c = @import("c");
const build_options = @import("build_options");

pub const ubrk_open = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("ubrk_open_{d}", .{build_options.icu_version})
    else
        "ubrk_open";
    break :blk @extern(*const @TypeOf(c.ubrk_open), .{ .name = name });
};

pub const ubrk_close = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("ubrk_close_{d}", .{build_options.icu_version})
    else
        "ubrk_close";
    break :blk @extern(*const @TypeOf(c.ubrk_close), .{ .name = name });
};

pub const ubrk_setText = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("ubrk_setText_{d}", .{build_options.icu_version})
    else
        "ubrk_setText";
    break :blk @extern(*const @TypeOf(c.ubrk_setText), .{ .name = name });
};

pub const ubrk_first = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("ubrk_first_{d}", .{build_options.icu_version})
    else
        "ubrk_first";
    break :blk @extern(*const @TypeOf(c.ubrk_first), .{ .name = name });
};

pub const ubrk_next = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("ubrk_next_{d}", .{build_options.icu_version})
    else
        "ubrk_next";
    break :blk @extern(*const @TypeOf(c.ubrk_next), .{ .name = name });
};

pub const ubrk_getRuleStatus = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("ubrk_getRuleStatus_{d}", .{build_options.icu_version})
    else
        "ubrk_getRuleStatus";
    break :blk @extern(*const @TypeOf(c.ubrk_getRuleStatus), .{ .name = name });
};

pub const ubrk_clone = if (@hasDecl(c, "ubrk_clone")) blk: {
    const name = if (build_options.icu_version > 0 and build_options.has_ubrk_clone)
        std.fmt.comptimePrint("ubrk_clone_{d}", .{build_options.icu_version})
    else
        "ubrk_clone";
    break :blk @extern(*const @TypeOf(c.ubrk_clone), .{ .name = name });
} else @compileError("ICU function 'ubrk_clone' not found");

pub const u_strToUTF8WithSub = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("u_strToUTF8WithSub_{d}", .{build_options.icu_version})
    else
        "u_strToUTF8WithSub";
    break :blk @extern(*const @TypeOf(c.u_strToUTF8WithSub), .{ .name = name });
};

pub const u_strToUTF8 = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("u_strToUTF8_{d}", .{build_options.icu_version})
    else
        "u_strToUTF8";
    break :blk @extern(*const @TypeOf(c.u_strToUTF8), .{ .name = name });
};

pub const utrans_openU = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("utrans_openU_{d}", .{build_options.icu_version})
    else
        "utrans_openU";
    break :blk @extern(*const @TypeOf(c.utrans_openU), .{ .name = name });
};

pub const utrans_close = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("utrans_close_{d}", .{build_options.icu_version})
    else
        "utrans_close";
    break :blk @extern(*const @TypeOf(c.utrans_close), .{ .name = name });
};

pub const utrans_clone = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("utrans_clone_{d}", .{build_options.icu_version})
    else
        "utrans_clone";
    break :blk @extern(*const @TypeOf(c.utrans_clone), .{ .name = name });
};

pub const utrans_transUChars = blk: {
    const name = if (build_options.icu_version > 0)
        std.fmt.comptimePrint("utrans_transUChars_{d}", .{build_options.icu_version})
    else
        "utrans_transUChars";
    break :blk @extern(*const @TypeOf(c.utrans_transUChars), .{ .name = name });
};
