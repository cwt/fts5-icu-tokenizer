const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");

const icu_ver: u32 = if (builtin.os.tag.isDarwin()) 0 else @intCast(c.U_ICU_VERSION_MAJOR_NUM);

// Bug #22: single source of truth for ubrk_clone availability. Darwin's
// libicucore exports the unversioned symbol regardless of header version;
// elsewhere require a modern-enough ICU build macro.
pub const has_ubrk_clone = builtin.os.tag.isDarwin() or icu_ver >= 69;

pub const ubrk_open = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("ubrk_open_{d}", .{icu_ver})
    else
        "ubrk_open";
    break :blk @extern(*const @TypeOf(c.ubrk_open), .{ .name = name });
};

pub const ubrk_close = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("ubrk_close_{d}", .{icu_ver})
    else
        "ubrk_close";
    break :blk @extern(*const @TypeOf(c.ubrk_close), .{ .name = name });
};

pub const ubrk_setText = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("ubrk_setText_{d}", .{icu_ver})
    else
        "ubrk_setText";
    break :blk @extern(*const @TypeOf(c.ubrk_setText), .{ .name = name });
};

pub const ubrk_first = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("ubrk_first_{d}", .{icu_ver})
    else
        "ubrk_first";
    break :blk @extern(*const @TypeOf(c.ubrk_first), .{ .name = name });
};

pub const ubrk_next = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("ubrk_next_{d}", .{icu_ver})
    else
        "ubrk_next";
    break :blk @extern(*const @TypeOf(c.ubrk_next), .{ .name = name });
};

pub const ubrk_getRuleStatus = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("ubrk_getRuleStatus_{d}", .{icu_ver})
    else
        "ubrk_getRuleStatus";
    break :blk @extern(*const @TypeOf(c.ubrk_getRuleStatus), .{ .name = name });
};

// Bug #22: resolved through our own canonical function type rather than
// @TypeOf(c.ubrk_clone), and it degrades to `null` instead of @compileError
// when the linked ICU predates ubrk_clone — the runtime fallback branch in
// tokenizeText exists precisely for those builds, so they must still compile.
// Callers gate on `has_ubrk_clone`.
const UbrkCloneFn = *const fn (?*const c.UBreakIterator, ?*c.UErrorCode) callconv(.c) ?*c.UBreakIterator;

pub const ubrk_clone: ?UbrkCloneFn = if (has_ubrk_clone) blk: {
    const name = if (builtin.os.tag.isDarwin())
        "ubrk_clone"
    else
        std.fmt.comptimePrint("ubrk_clone_{d}", .{icu_ver});
    break :blk @extern(UbrkCloneFn, .{ .name = name });
} else null;

pub const u_strToUTF8WithSub = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("u_strToUTF8WithSub_{d}", .{icu_ver})
    else
        "u_strToUTF8WithSub";
    break :blk @extern(*const @TypeOf(c.u_strToUTF8WithSub), .{ .name = name });
};

pub const u_strToUTF8 = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("u_strToUTF8_{d}", .{icu_ver})
    else
        "u_strToUTF8";
    break :blk @extern(*const @TypeOf(c.u_strToUTF8), .{ .name = name });
};

pub const utrans_openU = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("utrans_openU_{d}", .{icu_ver})
    else
        "utrans_openU";
    break :blk @extern(*const @TypeOf(c.utrans_openU), .{ .name = name });
};

pub const utrans_close = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("utrans_close_{d}", .{icu_ver})
    else
        "utrans_close";
    break :blk @extern(*const @TypeOf(c.utrans_close), .{ .name = name });
};

pub const utrans_clone = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("utrans_clone_{d}", .{icu_ver})
    else
        "utrans_clone";
    break :blk @extern(*const @TypeOf(c.utrans_clone), .{ .name = name });
};

pub const utrans_transUChars = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("utrans_transUChars_{d}", .{icu_ver})
    else
        "utrans_transUChars";
    break :blk @extern(*const @TypeOf(c.utrans_transUChars), .{ .name = name });
};

pub const uloc_getLanguage = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("uloc_getLanguage_{d}", .{icu_ver})
    else
        "uloc_getLanguage";
    break :blk @extern(*const @TypeOf(c.uloc_getLanguage), .{ .name = name });
};

pub const uloc_getAvailable = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("uloc_getAvailable_{d}", .{icu_ver})
    else
        "uloc_getAvailable";
    break :blk @extern(*const @TypeOf(c.uloc_getAvailable), .{ .name = name });
};

pub const uloc_countAvailable = blk: {
    const name = if (icu_ver > 0)
        std.fmt.comptimePrint("uloc_countAvailable_{d}", .{icu_ver})
    else
        "uloc_countAvailable";
    break :blk @extern(*const @TypeOf(c.uloc_countAvailable), .{ .name = name });
};
