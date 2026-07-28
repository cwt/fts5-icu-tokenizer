const std = @import("std");
const c = @import("c");
const build_options = @import("build_options");

pub const ubrk_open = blk: {
    const name = "ubrk_open";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.ubrk_open;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const ubrk_close = blk: {
    const name = "ubrk_close";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.ubrk_close;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const ubrk_setText = blk: {
    const name = "ubrk_setText";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.ubrk_setText;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const ubrk_first = blk: {
    const name = "ubrk_first";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.ubrk_first;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const ubrk_next = blk: {
    const name = "ubrk_next";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.ubrk_next;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const ubrk_getRuleStatus = blk: {
    const name = "ubrk_getRuleStatus";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.ubrk_getRuleStatus;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const u_strFromUTF8 = blk: {
    const name = "u_strFromUTF8";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.u_strFromUTF8;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const u_strToUTF8WithSub = blk: {
    const name = "u_strToUTF8WithSub";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.u_strToUTF8WithSub;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const u_strToUTF8 = blk: {
    const name = "u_strToUTF8";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.u_strToUTF8;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const utrans_openU = blk: {
    const name = "utrans_openU";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.utrans_openU;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const utrans_close = blk: {
    const name = "utrans_close";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.utrans_close;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const utrans_clone = blk: {
    const name = "utrans_clone";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.utrans_clone;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};

pub const utrans_transUChars = blk: {
    const name = "utrans_transUChars";
    @setEvalBranchQuota(2000);
    if (@hasDecl(c, name)) break :blk c.utrans_transUChars;
    if (build_options.icu_version > 0 and @hasDecl(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version})))
        break :blk @field(c, std.fmt.comptimePrint(name ++ "_{d}", .{build_options.icu_version}));
    @compileError("ICU function '" ++ name ++ "' not found");
};
