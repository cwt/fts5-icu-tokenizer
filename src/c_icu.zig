const std = @import("std");
const c = @import("c");

const icu_ver: u32 = @intCast(c.U_ICU_VERSION_MAJOR_NUM);

// Bug #22: single source of truth for ubrk_clone availability. ICU >= 69
// provides ubrk_clone (replacing deprecated ubrk_safeClone).
pub const has_ubrk_clone = icu_ver >= 69;

// Bug #34: one name helper instead of fifteen near-identical version
// branches. Each resolution keeps its explicit short symbol string, so
// grepping for a symbol name still finds it. (A fuller helper returning
// `@extern(T, ...)` from a generic function is rejected: @extern needs a
// concrete pointer type, so the call stays at container scope.)
fn icuName(comptime short: []const u8) [:0]const u8 {
    return std.fmt.comptimePrint("{s}_{d}", .{ short, icu_ver });
}

pub const ubrk_open = @extern(*const @TypeOf(c.ubrk_open), .{ .name = icuName("ubrk_open") });
pub const ubrk_close = @extern(*const @TypeOf(c.ubrk_close), .{ .name = icuName("ubrk_close") });
pub const ubrk_setText = @extern(*const @TypeOf(c.ubrk_setText), .{ .name = icuName("ubrk_setText") });
pub const ubrk_first = @extern(*const @TypeOf(c.ubrk_first), .{ .name = icuName("ubrk_first") });
pub const ubrk_next = @extern(*const @TypeOf(c.ubrk_next), .{ .name = icuName("ubrk_next") });
pub const ubrk_getRuleStatus = @extern(*const @TypeOf(c.ubrk_getRuleStatus), .{ .name = icuName("ubrk_getRuleStatus") });

// Bug #22: resolved through our own canonical function type rather than
// @TypeOf(c.ubrk_clone), and it degrades to `null` instead of @compileError
// when the linked ICU predates ubrk_clone — the runtime fallback branch in
// tokenizeText exists precisely for those builds, so they must still compile.
// Callers gate on `has_ubrk_clone`.
const UbrkCloneFn = *const fn (?*const c.UBreakIterator, ?*c.UErrorCode) callconv(.c) ?*c.UBreakIterator;

pub const ubrk_clone: ?UbrkCloneFn = if (has_ubrk_clone)
    @extern(UbrkCloneFn, .{ .name = icuName("ubrk_clone") })
else
    null;

pub const u_strToUTF8WithSub = @extern(*const @TypeOf(c.u_strToUTF8WithSub), .{ .name = icuName("u_strToUTF8WithSub") });
pub const u_strToUTF8 = @extern(*const @TypeOf(c.u_strToUTF8), .{ .name = icuName("u_strToUTF8") });
pub const utrans_openU = @extern(*const @TypeOf(c.utrans_openU), .{ .name = icuName("utrans_openU") });
pub const utrans_close = @extern(*const @TypeOf(c.utrans_close), .{ .name = icuName("utrans_close") });
pub const utrans_clone = @extern(*const @TypeOf(c.utrans_clone), .{ .name = icuName("utrans_clone") });
pub const utrans_transUChars = @extern(*const @TypeOf(c.utrans_transUChars), .{ .name = icuName("utrans_transUChars") });
pub const uloc_getLanguage = @extern(*const @TypeOf(c.uloc_getLanguage), .{ .name = icuName("uloc_getLanguage") });
pub const uloc_getAvailable = @extern(*const @TypeOf(c.uloc_getAvailable), .{ .name = icuName("uloc_getAvailable") });
pub const uloc_countAvailable = @extern(*const @TypeOf(c.uloc_countAvailable), .{ .name = icuName("uloc_countAvailable") });
