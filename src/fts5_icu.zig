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

const fts5_api = extern struct {
    iVersion: c_int,
    xCreateTokenizer: ?*const fn (?*fts5_api, [*c]const u8, ?*anyopaque, *fts5_tokenizer, ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) c_int,
    xFindTokenizer: ?*const fn (?*fts5_api, [*c]const u8, [*c]?*anyopaque, *fts5_tokenizer) callconv(.c) c_int,
    xCreateTokenizer_v2: ?*const fn (?*fts5_api, [*c]const u8, ?*anyopaque, *fts5_tokenizer_v2, ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) c_int,
    xFindTokenizer_v2: ?*const fn (?*fts5_api, [*c]const u8, [*c]?*anyopaque, *fts5_tokenizer_v2) callconv(.c) c_int,
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
    if (nArg > 0 and azArg != null and azArg[0] != null and azArg[0][0] != 0) {
        locale = std.mem.span(azArg[0]);
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

fn initExtensionForLocaleV2(
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
    if (api.iVersion < 2) {
        if (pApi.mprintf) |mprintf_fn| {
            pzErrMsg.* = mprintf_fn("FTS5 v2 API not available");
        }
        return c.SQLITE_ERROR;
    }

    var tokenizer_v2 = fts5_tokenizer_v2{
        .iVersion = 2,
        .xCreate = icuCreate,
        .xDelete = icuDelete,
        .xTokenize = icuTokenizeV2,
    };

    const tok_name = rules.getTokenizerNameForLocale(locale);
    const tok_name_c = std.heap.c_allocator.dupeZ(u8, tok_name) catch return c.SQLITE_NOMEM;
    defer std.heap.c_allocator.free(tok_name_c);

    const rc = api.xCreateTokenizer_v2.?(api, tok_name_c.ptr, null, &tokenizer_v2, null);
    if (rc != c.SQLITE_OK) {
        if (pApi.mprintf) |mprintf_fn| {
            const err_msg: [*c]const u8 = if (pApi.errstr) |errstr_fn| errstr_fn(rc) else "unknown error";
            pzErrMsg.* = mprintf_fn("Failed to register ICU tokenizer: %s", err_msg);
        }
    }
    return rc;
}

fn initExtensionForLocaleV1(
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
    var tokenizer_v1 = fts5_tokenizer{
        .xCreate = icuCreate,
        .xDelete = icuDelete,
        .xTokenize = icuTokenizeV1,
    };

    const tok_name = rules.getTokenizerNameForLocale(locale);
    const tok_name_c = std.heap.c_allocator.dupeZ(u8, tok_name) catch return c.SQLITE_NOMEM;
    defer std.heap.c_allocator.free(tok_name_c);

    const rc = api.xCreateTokenizer.?(api, tok_name_c.ptr, null, &tokenizer_v1, null);
    if (rc != c.SQLITE_OK) {
        if (pApi.mprintf) |mprintf_fn| {
            const err_msg: [*c]const u8 = if (pApi.errstr) |errstr_fn| errstr_fn(rc) else "unknown error";
            pzErrMsg.* = mprintf_fn("Failed to register ICU tokenizer (legacy): %s", err_msg);
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
    if (std.mem.eql(u8, build_options.api_version, "v1")) {
        return initExtensionForLocaleV1(db, pzErrMsg, pApi, locale);
    } else {
        return initExtensionForLocaleV2(db, pzErrMsg, pApi, locale);
    }
}

// === FTS5 v2 Exported Entrypoints ===
pub export fn sqlite3_ftsicu_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocale(db.?, pzErrMsg, pApi.?, build_options.locale);
}

pub export fn sqlite3_ftsicuja_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocale(db.?, pzErrMsg, pApi.?, "ja");
}
pub export fn sqlite3_ftsicu_ja_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuja_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuzh_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocale(db.?, pzErrMsg, pApi.?, "zh");
}
pub export fn sqlite3_ftsicu_zh_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuzh_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuth_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocale(db.?, pzErrMsg, pApi.?, "th");
}
pub export fn sqlite3_ftsicu_th_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuth_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuko_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocale(db.?, pzErrMsg, pApi.?, "ko");
}
pub export fn sqlite3_ftsicu_ko_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuko_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuar_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocale(db.?, pzErrMsg, pApi.?, "ar");
}
pub export fn sqlite3_ftsicu_ar_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuar_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuru_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocale(db.?, pzErrMsg, pApi.?, "ru");
}
pub export fn sqlite3_ftsicu_ru_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuru_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuhe_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocale(db.?, pzErrMsg, pApi.?, "he");
}
pub export fn sqlite3_ftsicu_he_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuhe_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuel_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocale(db.?, pzErrMsg, pApi.?, "el");
}
pub export fn sqlite3_ftsicu_el_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuel_init(db, pzErrMsg, pApi);
}

// === FTS5 v1 (Legacy) Exported Entrypoints ===
pub export fn sqlite3_ftsicu_legacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocaleV1(db.?, pzErrMsg, pApi.?, build_options.locale);
}
pub export fn sqlite3_ftsiculegacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicu_legacy_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuja_legacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocaleV1(db.?, pzErrMsg, pApi.?, "ja");
}
pub export fn sqlite3_ftsicujalegacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuja_legacy_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuzh_legacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocaleV1(db.?, pzErrMsg, pApi.?, "zh");
}
pub export fn sqlite3_ftsicuzhlegacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuzh_legacy_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuth_legacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocaleV1(db.?, pzErrMsg, pApi.?, "th");
}
pub export fn sqlite3_ftsicuthlegacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuth_legacy_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuko_legacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocaleV1(db.?, pzErrMsg, pApi.?, "ko");
}
pub export fn sqlite3_ftsicukolegacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuko_legacy_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuar_legacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocaleV1(db.?, pzErrMsg, pApi.?, "ar");
}
pub export fn sqlite3_ftsicuarlegacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuar_legacy_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuru_legacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocaleV1(db.?, pzErrMsg, pApi.?, "ru");
}
pub export fn sqlite3_ftsicurulegacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuru_legacy_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuhe_legacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocaleV1(db.?, pzErrMsg, pApi.?, "he");
}
pub export fn sqlite3_ftsicuhelegacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuhe_legacy_init(db, pzErrMsg, pApi);
}

pub export fn sqlite3_ftsicuel_legacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    if (db == null or pApi == null) return c.SQLITE_ERROR;
    return initExtensionForLocaleV1(db.?, pzErrMsg, pApi.?, "el");
}
pub export fn sqlite3_ftsicuellegacy_init(db: ?*c.sqlite3, pzErrMsg: [*c][*c]u8, pApi: ?*const c.sqlite3_api_routines) callconv(.c) c_int {
    return sqlite3_ftsicuel_legacy_init(db, pzErrMsg, pApi);
}

test "version string" {
    try std.testing.expectEqualStrings("6.0.2", VERSION);
}
