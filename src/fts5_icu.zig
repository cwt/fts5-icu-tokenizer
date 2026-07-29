const std = @import("std");
const c = @import("c");
const build_options = @import("build_options");
const rules = @import("rules.zig");
const tokenizer = @import("tokenizer.zig");

pub const VERSION = build_options.version;

const Fts5Tokenizer = opaque {};

const fts5_tokenizer = extern struct {
    xCreate: ?*const fn (?*anyopaque, [*c][*c]const u8, c_int, [*c]?*Fts5Tokenizer) callconv(.c) c_int,
    xDelete: ?*const fn (?*Fts5Tokenizer) callconv(.c) void,
    xTokenize: ?*const fn (?*Fts5Tokenizer, ?*anyopaque, c_int, [*c]const u8, c_int, ?*const fn (?*anyopaque, c_int, [*c]const u8, c_int, c_int, c_int) callconv(.c) c_int) callconv(.c) c_int,
};

const fts5_tokenizer_v2 = extern struct {
    iVersion: c_int,
    xCreate: ?*const fn (?*anyopaque, [*c][*c]const u8, c_int, [*c]?*Fts5Tokenizer) callconv(.c) c_int,
    xDelete: ?*const fn (?*Fts5Tokenizer) callconv(.c) void,
    xTokenize: ?*const fn (?*Fts5Tokenizer, ?*anyopaque, c_int, [*c]const u8, c_int, [*c]const u8, c_int, ?*const fn (?*anyopaque, c_int, [*c]const u8, c_int, c_int, c_int) callconv(.c) c_int) callconv(.c) c_int,
};

const fts5_extension_function = ?*const fn (
    [*c]const fts5_api,
    ?*anyopaque,
    ?*c.sqlite3_context,
    c_int,
    [*c]?*c.sqlite3_value,
) callconv(.c) void;

const fts5_api = extern struct {
    iVersion: c_int,
    xCreateTokenizer: ?*const fn (?*fts5_api, [*c]const u8, ?*anyopaque, *fts5_tokenizer, ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) c_int,
    xFindTokenizer: ?*const fn (?*fts5_api, [*c]const u8, [*c]?*anyopaque, *fts5_tokenizer) callconv(.c) c_int,
    xCreateFunction: ?*const fn (?*fts5_api, [*c]const u8, ?*anyopaque, fts5_extension_function, ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) c_int,
    xCreateTokenizer_v2: ?*const fn (?*fts5_api, [*c]const u8, ?*anyopaque, *fts5_tokenizer_v2, ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) c_int,
    xFindTokenizer_v2: ?*const fn (?*fts5_api, [*c]const u8, [*c]?*anyopaque, [*c]*fts5_tokenizer_v2) callconv(.c) c_int,
};

pub export var sqlite3_api: [*c]const c.sqlite3_api_routines = null;

pub export fn fts5_icu_version() callconv(.c) [*c]const u8 {
    return VERSION.ptr;
}

fn fts5_icu_version_sql(
    ctx: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.c) void {
    _ = argc;
    _ = argv;
    if (sqlite3_api) |api| {
        if (api.*.result_text) |res_text| {
            res_text(ctx, VERSION.ptr, @intCast(VERSION.len), c.SQLITE_STATIC);
        }
    }
}

// FTS5 callback: xCreate (common for v1 & v2)
fn icuCreate(
    pCtx: ?*anyopaque,
    azArg: [*c][*c]const u8,
    nArg: c_int,
    ppOut: [*c]?*Fts5Tokenizer,
) callconv(.c) c_int {
    _ = pCtx;
    var locale: []const u8 = build_options.locale;
    // FTS5 passes the tokenizer NAME as azArg[0]; an optional locale override is
    // the SECOND argument (e.g. `tokenize = 'icu th'`), matching SQLite's own
    // fts5_icu.c (`nArg > 1 -> azArg[1]`). The baked-in `build_options.locale`
    // is already correct for this library, so only honor a SECOND argument as
    // an explicit locale override. Reading azArg[0] as the locale (the previous
    // behavior) made every locale-specific library use the wrong ICU locale.
    if (nArg > 1 and azArg != null and azArg[1] != null and azArg[1][0] != 0) {
        locale = std.mem.span(azArg[1]);
    }

    const tok = tokenizer.IcuTokenizer.create(std.heap.c_allocator, locale) catch {
        return c.SQLITE_ERROR;
    };

    ppOut.* = @ptrCast(tok);
    return c.SQLITE_OK;
}

// FTS5 callback: xDelete (common for v1 & v2)
fn icuDelete(pTok: ?*Fts5Tokenizer) callconv(.c) void {
    if (pTok) |pt| {
        const tok: *tokenizer.IcuTokenizer = @ptrCast(@alignCast(pt));
        tok.destroy(std.heap.c_allocator);
    }
}

// FTS5 v2 callback: xTokenize
fn icuTokenizeV2(
    pTok: ?*Fts5Tokenizer,
    pCtx: ?*anyopaque,
    flags: c_int,
    pText: [*c]const u8,
    nText: c_int,
    pLocale: [*c]const u8,
    nLocale: c_int,
    xToken: ?*const fn (?*anyopaque, c_int, [*c]const u8, c_int, c_int, c_int) callconv(.c) c_int,
) callconv(.c) c_int {
    _ = flags;
    if (pTok == null or pText == null or nText <= 0 or xToken == null) {
        return c.SQLITE_OK;
    }

    const tok: *tokenizer.IcuTokenizer = @ptrCast(@alignCast(pTok));
    const text = pText[0..@intCast(nText)];

    var override_locale: ?[]const u8 = null;
    if (pLocale != null and nLocale > 0) {
        override_locale = pLocale[0..@intCast(nLocale)];
    }

    return tokenizer.tokenizeText(
        std.heap.c_allocator,
        tok,
        text,
        override_locale,
        pCtx,
        xToken.?,
    ) catch c.SQLITE_ERROR;
}

// FTS5 v1 (legacy) callback: xTokenize
fn icuTokenizeV1(
    pTok: ?*Fts5Tokenizer,
    pCtx: ?*anyopaque,
    flags: c_int,
    pText: [*c]const u8,
    nText: c_int,
    xToken: ?*const fn (?*anyopaque, c_int, [*c]const u8, c_int, c_int, c_int) callconv(.c) c_int,
) callconv(.c) c_int {
    _ = flags;
    if (pTok == null or pText == null or nText <= 0 or xToken == null) {
        return c.SQLITE_OK;
    }

    const tok: *tokenizer.IcuTokenizer = @ptrCast(@alignCast(pTok));
    const text = pText[0..@intCast(nText)];

    return tokenizer.tokenizeText(
        std.heap.c_allocator,
        tok,
        text,
        null,
        pCtx,
        xToken.?,
    ) catch c.SQLITE_ERROR;
}

fn getFts5Api(db: *c.sqlite3, pApi: *const c.sqlite3_api_routines) ?*fts5_api {
    var pFts5Api: ?*fts5_api = null;
    var pStmt: ?*c.sqlite3_stmt = null;
    if (pApi.prepare_v2) |prep_fn| {
        if (prep_fn(db, "SELECT fts5(?)", -1, &pStmt, null) == c.SQLITE_OK) {
            if (pApi.bind_pointer) |bind_ptr| {
                _ = bind_ptr(pStmt, 1, @ptrCast(&pFts5Api), "fts5_api_ptr", null);
            }
            if (pApi.step) |step_fn| {
                _ = step_fn(pStmt);
            }
            if (pApi.finalize) |fin_fn| {
                _ = fin_fn(pStmt);
            }
        }
    }
    return pFts5Api;
}

var global_tokenizer_v2 = fts5_tokenizer_v2{
    .iVersion = 2,
    .xCreate = icuCreate,
    .xDelete = icuDelete,
    .xTokenize = icuTokenizeV2,
};

var global_tokenizer_v1 = fts5_tokenizer{
    .xCreate = icuCreate,
    .xDelete = icuDelete,
    .xTokenize = icuTokenizeV1,
};

fn initExtensionForLocaleInner(
    use_v2: bool,
    db: *c.sqlite3,
    pzErrMsg: [*c][*c]u8,
    pApi: *const c.sqlite3_api_routines,
    locale: []const u8,
) c_int {
    sqlite3_api = pApi;

    if (pApi.create_function) |create_fn| {
        _ = create_fn(db, "fts5_icu_version", 0, c.SQLITE_UTF8 | c.SQLITE_DETERMINISTIC, null, fts5_icu_version_sql, null, null);
    }

    const pFts5Api = getFts5Api(db, pApi);
    if (pFts5Api == null) {
        if (pApi.mprintf) |mprintf_fn| {
            pzErrMsg.* = mprintf_fn("Failed to get FTS5 API");
        }
        return c.SQLITE_ERROR;
    }

    const api = pFts5Api.?;
    if (use_v2) {
        if (api.iVersion < 3) {
            if (pApi.mprintf) |mprintf_fn| {
                pzErrMsg.* = mprintf_fn("FTS5 v2 API not available");
            }
            return c.SQLITE_ERROR;
        }
    }

    const tok_name = rules.getTokenizerNameForLocale(locale);
    const tok_name_c = std.heap.c_allocator.dupeZ(u8, tok_name) catch return c.SQLITE_NOMEM;
    defer std.heap.c_allocator.free(tok_name_c);

    const rc = if (use_v2)
        api.xCreateTokenizer_v2.?(api, tok_name_c.ptr, null, &global_tokenizer_v2, null)
    else
        api.xCreateTokenizer.?(api, tok_name_c.ptr, null, &global_tokenizer_v1, null);

    if (rc != c.SQLITE_OK) {
        if (pApi.mprintf) |mprintf_fn| {
            const err_msg: [*c]const u8 = if (pApi.errstr) |errstr_fn| errstr_fn(rc) else "unknown error";
            const fmt: [*c]const u8 = if (use_v2)
                "Failed to register ICU tokenizer: %s"
            else
                "Failed to register ICU tokenizer (legacy): %s";
            pzErrMsg.* = mprintf_fn(fmt, err_msg);
        }
    }
    return rc;
}

fn initExtensionForLocale(
    db: *c.sqlite3,
    pzErrMsg: [*c][*c]u8,
    pApi: *const c.sqlite3_api_routines,
    locale: []const u8,
) c_int {
    const use_v2 = !std.mem.eql(u8, build_options.api_version, "v1");
    return initExtensionForLocaleInner(use_v2, db, pzErrMsg, pApi, locale);
}

fn initExtensionForLocaleV1(
    db: *c.sqlite3,
    pzErrMsg: [*c][*c]u8,
    pApi: *const c.sqlite3_api_routines,
    locale: []const u8,
) c_int {
    return initExtensionForLocaleInner(false, db, pzErrMsg, pApi, locale);
}

// === Exported Entrypoints (generated) ===
//
// Each SQLite auto-extension entry point is a thin wrapper that performs the
// null checks and delegates to initExtensionForLocale / initExtensionForLocaleV1.
// They are generated at comptime to remove the ~35 near-identical `pub export fn`
// definitions that previously lived here (Bug #6). The exported symbol names are
// kept byte-for-byte identical to the previous hand-written entry points, so every
// existing `.load` invocation continues to work unchanged.

fn entrypointType(
    comptime locale: []const u8,
    comptime legacy: bool,
) type {
    return struct {
        fn init(
            db: ?*c.sqlite3,
            pzErrMsg: [*c][*c]u8,
            pApi: ?*const c.sqlite3_api_routines,
        ) callconv(.c) c_int {
            if (db == null or pApi == null) return c.SQLITE_ERROR;
            if (legacy) {
                return initExtensionForLocaleV1(db.?, pzErrMsg, pApi.?, locale);
            }
            return initExtensionForLocale(db.?, pzErrMsg, pApi.?, locale);
        }
    };
}

const entrypoints = [_]struct {
    name: []const u8,
    locale: []const u8,
    legacy: bool,
}{
    .{ .name = "sqlite3_ftsicu_init", .locale = build_options.locale, .legacy = false },
    .{ .name = "sqlite3_ftsicu_legacy_init", .locale = build_options.locale, .legacy = true },
    .{ .name = "sqlite3_ftsiculegacy_init", .locale = build_options.locale, .legacy = true },

    .{ .name = "sqlite3_ftsicuja_init", .locale = "ja", .legacy = false },
    .{ .name = "sqlite3_ftsicu_ja_init", .locale = "ja", .legacy = false },
    .{ .name = "sqlite3_ftsicuja_legacy_init", .locale = "ja", .legacy = true },
    .{ .name = "sqlite3_ftsicujalegacy_init", .locale = "ja", .legacy = true },

    .{ .name = "sqlite3_ftsicuzh_init", .locale = "zh", .legacy = false },
    .{ .name = "sqlite3_ftsicu_zh_init", .locale = "zh", .legacy = false },
    .{ .name = "sqlite3_ftsicuzh_legacy_init", .locale = "zh", .legacy = true },
    .{ .name = "sqlite3_ftsicuzhlegacy_init", .locale = "zh", .legacy = true },

    .{ .name = "sqlite3_ftsicuth_init", .locale = "th", .legacy = false },
    .{ .name = "sqlite3_ftsicu_th_init", .locale = "th", .legacy = false },
    .{ .name = "sqlite3_ftsicuth_legacy_init", .locale = "th", .legacy = true },
    .{ .name = "sqlite3_ftsicuthlegacy_init", .locale = "th", .legacy = true },

    .{ .name = "sqlite3_ftsicuko_init", .locale = "ko", .legacy = false },
    .{ .name = "sqlite3_ftsicu_ko_init", .locale = "ko", .legacy = false },
    .{ .name = "sqlite3_ftsicuko_legacy_init", .locale = "ko", .legacy = true },
    .{ .name = "sqlite3_ftsicukolegacy_init", .locale = "ko", .legacy = true },

    .{ .name = "sqlite3_ftsicuar_init", .locale = "ar", .legacy = false },
    .{ .name = "sqlite3_ftsicu_ar_init", .locale = "ar", .legacy = false },
    .{ .name = "sqlite3_ftsicuar_legacy_init", .locale = "ar", .legacy = true },
    .{ .name = "sqlite3_ftsicuarlegacy_init", .locale = "ar", .legacy = true },

    .{ .name = "sqlite3_ftsicuru_init", .locale = "ru", .legacy = false },
    .{ .name = "sqlite3_ftsicu_ru_init", .locale = "ru", .legacy = false },
    .{ .name = "sqlite3_ftsicuru_legacy_init", .locale = "ru", .legacy = true },
    .{ .name = "sqlite3_ftsicurulegacy_init", .locale = "ru", .legacy = true },

    .{ .name = "sqlite3_ftsicuhe_init", .locale = "he", .legacy = false },
    .{ .name = "sqlite3_ftsicu_he_init", .locale = "he", .legacy = false },
    .{ .name = "sqlite3_ftsicuhe_legacy_init", .locale = "he", .legacy = true },
    .{ .name = "sqlite3_ftsicuhelegacy_init", .locale = "he", .legacy = true },

    .{ .name = "sqlite3_ftsicuel_init", .locale = "el", .legacy = false },
    .{ .name = "sqlite3_ftsicu_el_init", .locale = "el", .legacy = false },
    .{ .name = "sqlite3_ftsicuel_legacy_init", .locale = "el", .legacy = true },
    .{ .name = "sqlite3_ftsicuellegacy_init", .locale = "el", .legacy = true },
};

comptime {
    for (entrypoints) |ep| {
        @export(&entrypointType(ep.locale, ep.legacy).init, .{ .name = ep.name });
    }
}

test "version string" {
    try std.testing.expectEqualStrings("6.0.3", VERSION);
}

// Bug #6: the SQLite entry points used to be ~35 hand-written, near-identical
// `pub export fn` definitions. They are now generated from this single table.
// This test guards the dedup against regressions (missing/duplicate symbols,
// wrong count) so the generated set stays in sync with what callers `.load`.
test "entrypoint table integrity" {
    // 1 universal v2 + 1 universal legacy (+1 universal legacy alias) + 8 locales x 4.
    try std.testing.expectEqual(@as(usize, 35), entrypoints.len);

    // Every exported symbol name must be unique.
    for (entrypoints, 0..) |a, i| {
        for (entrypoints[i + 1 ..]) |b| {
            try std.testing.expect(!std.mem.eql(u8, a.name, b.name));
        }
    }

    // The canonical universal entry points must be present.
    var has_universal = false;
    var has_universal_legacy = false;
    for (entrypoints) |ep| {
        if (std.mem.eql(u8, ep.name, "sqlite3_ftsicu_init")) has_universal = true;
        if (std.mem.eql(u8, ep.name, "sqlite3_ftsicu_legacy_init")) has_universal_legacy = true;
    }
    try std.testing.expect(has_universal);
    try std.testing.expect(has_universal_legacy);
}

// Bug #9: FTS5's xCreate receives the tokenizer NAME as azArg[0] and an
// optional locale override as azArg[1] (SQLite's own fts5_icu.c reads
// `nArg > 1 -> azArg[1]`). The previous code treated azArg[0] as the locale,
// so `tokenize = 'icu_ja'` set locale = "icu_ja" (an invalid ICU locale),
// making every locale-specific library use the wrong word-breaking and
// transliteration rules. This test checks that icuCreate ignores the name and
// only honors a SECOND argument as the locale override. (In the universal test
// build build_options.locale == "".)
test "icuCreate ignores tokenizer name, uses arg[1] as locale (bug #9)" {
    var ppOut: ?*Fts5Tokenizer = null;

    // Case 1: azArg[0] = "icu_ja" (the tokenizer name), no override -> locale
    // must stay build_options.locale, NOT "icu_ja".
    const arg0 = "icu_ja";
    var azArg0 = [_][*c]const u8{arg0.ptr};
    const rc1 = icuCreate(null, &azArg0, 1, &ppOut);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc1);
    {
        const tok: *tokenizer.IcuTokenizer = @ptrCast(@alignCast(ppOut.?));
        try std.testing.expectEqualStrings(build_options.locale, tok.locale_slice);
        tok.destroy(std.heap.c_allocator);
    }

    // Case 2: azArg[0] = "icu", azArg[1] = "th" -> explicit locale override to
    // "th".
    const arg1a = "icu";
    const arg1b = "th";
    var azArg1 = [_][*c]const u8{ arg1a.ptr, arg1b.ptr };
    const rc2 = icuCreate(null, &azArg1, 2, &ppOut);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc2);
    {
        const tok: *tokenizer.IcuTokenizer = @ptrCast(@alignCast(ppOut.?));
        try std.testing.expectEqualStrings("th", tok.locale_slice);
        tok.destroy(std.heap.c_allocator);
    }
}
