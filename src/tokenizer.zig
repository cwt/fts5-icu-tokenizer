const std = @import("std");
const c = @import("c");
const rules = @import("rules.zig");

pub const IcuTokenizer = struct {
    pBreakIterator: ?*c.UBreakIterator,
    pTransliterator: ?*c.UTransliterator,

    pub fn create(allocator: std.mem.Allocator, locale: []const u8) !*IcuTokenizer {
        var status: c.UErrorCode = c.U_ZERO_ERROR;

        const tok = try allocator.create(IcuTokenizer);
        errdefer allocator.destroy(tok);
        tok.* = .{
            .pBreakIterator = null,
            .pTransliterator = null,
        };

        const rule_str = rules.getRulesForLocale(locale);

        // Convert rule string to UTF-16
        const rules_u16 = try utf8ToUtf16Alloc(allocator, rule_str);
        defer allocator.free(rules_u16);

        // Convert locale string to zero-terminated C string
        const locale_c = try allocator.dupeZ(u8, locale);
        defer allocator.free(locale_c);

        tok.pBreakIterator = c.fts5_ubrk_open(c.UBRK_WORD, locale_c.ptr, null, 0, &status);
        if (c.U_FAILURE(status) or tok.pBreakIterator == null) {
            return error.IcuBreakIteratorFailed;
        }
        errdefer {
            if (tok.pBreakIterator) |bi| c.fts5_ubrk_close(bi);
        }

        status = c.U_ZERO_ERROR;
        tok.pTransliterator = c.fts5_utrans_openU(rules_u16.ptr, -1, c.UTRANS_FORWARD, null, 0, null, &status);
        if (c.U_FAILURE(status) or tok.pTransliterator == null) {
            return error.IcuTransliteratorFailed;
        }

        return tok;
    }

    pub fn destroy(self: *IcuTokenizer, allocator: std.mem.Allocator) void {
        if (self.pBreakIterator) |bi| c.fts5_ubrk_close(bi);
        if (self.pTransliterator) |tr| c.fts5_utrans_close(tr);
        allocator.destroy(self);
    }
};

pub fn utf8ToUtf16Alloc(allocator: std.mem.Allocator, text: []const u8) ![:0]c.UChar {
    if (text.len == 0) {
        const buf = try allocator.allocSentinel(c.UChar, 0, 0);
        return buf;
    }
    var status: c.UErrorCode = c.U_ZERO_ERROR;
    var len: i32 = 0;
    _ = c.fts5_u_strFromUTF8(null, 0, &len, text.ptr, @intCast(text.len), &status);
    if (status != c.U_BUFFER_OVERFLOW_ERROR and status != c.U_ZERO_ERROR) {
        return error.UCharConversionFailed;
    }
    status = c.U_ZERO_ERROR;
    const ulen: usize = @intCast(len);
    const buf = try allocator.allocSentinel(c.UChar, ulen, 0);
    errdefer allocator.free(buf);
    _ = c.fts5_u_strFromUTF8(buf.ptr, @intCast(ulen + 1), null, text.ptr, @intCast(text.len), &status);
    if (c.U_FAILURE(status)) {
        return error.UCharConversionFailed;
    }
    return buf;
}

pub fn tokenizeText(
    allocator: std.mem.Allocator,
    tokenizer: *IcuTokenizer,
    text: []const u8,
    override_locale: ?[]const u8,
    pCtx: ?*anyopaque,
    xToken: *const fn (?*anyopaque, c_int, [*c]const u8, c_int, c_int, c_int) callconv(.c) c_int,
) !c_int {
    if (text.len == 0) return c.SQLITE_OK;

    // Buffer allocation for UTF-16 text and byte offset map
    const utf16_buffer_size = text.len * 2 + 1;
    const map_buffer_size = text.len * 2 + 2;

    const utf16_text_buffer = try allocator.alloc(c.UChar, utf16_buffer_size);
    defer allocator.free(utf16_text_buffer);

    const byte_offset_map = try allocator.alloc(i32, map_buffer_size);
    defer allocator.free(byte_offset_map);

    // Convert UTF-8 to UTF-16 with byte offset mapping
    var utf16_pos: usize = 0;
    var utf8_pos: usize = 0;
    while (utf8_pos < text.len and utf16_pos < utf16_buffer_size) {
        const orig_utf8 = utf8_pos;
        const cp_len = std.unicode.utf8ByteSequenceLength(text[utf8_pos]) catch 1;
        const end = @min(utf8_pos + cp_len, text.len);
        const cp = std.unicode.utf8Decode(text[utf8_pos..end]) catch 0xFFFD;
        utf8_pos = end;

        const orig_utf16 = utf16_pos;
        if (cp <= 0xFFFF) {
            utf16_text_buffer[utf16_pos] = @intCast(cp);
            utf16_pos += 1;
        } else {
            if (utf16_pos + 2 > utf16_buffer_size) break;
            utf16_text_buffer[utf16_pos] = @intCast(0xD800 + ((cp - 0x10000) >> 10));
            utf16_text_buffer[utf16_pos + 1] = @intCast(0xDC00 + ((cp - 0x10000) & 0x3FF));
            utf16_pos += 2;
        }

        if (orig_utf16 < map_buffer_size) {
            byte_offset_map[orig_utf16] = @intCast(orig_utf8);
        }
        if (cp > 0xFFFF and orig_utf16 + 1 < map_buffer_size) {
            byte_offset_map[orig_utf16 + 1] = @intCast(orig_utf8);
        }
    }
    if (utf16_pos < map_buffer_size) {
        byte_offset_map[utf16_pos] = @intCast(text.len);
    }

    var pBreakIterator = tokenizer.pBreakIterator.?;
    var pTransliterator = tokenizer.pTransliterator.?;

    var dynBreak: ?*c.UBreakIterator = null;
    var dynTrans: ?*c.UTransliterator = null;
    defer {
        if (dynBreak) |b| c.fts5_ubrk_close(b);
        if (dynTrans) |t| c.fts5_utrans_close(t);
    }

    if (override_locale) |loc| {
        if (loc.len > 0) {
            var status: c.UErrorCode = c.U_ZERO_ERROR;
            const loc_c = try allocator.dupeZ(u8, loc);
            defer allocator.free(loc_c);

            const dyn_rules = rules.getRulesForLocale(loc);
            const dyn_rules_u16 = try utf8ToUtf16Alloc(allocator, dyn_rules);
            defer allocator.free(dyn_rules_u16);

            dynBreak = c.fts5_ubrk_open(c.UBRK_WORD, loc_c.ptr, null, 0, &status);
            if (c.U_FAILURE(status) or dynBreak == null) {
                return c.SQLITE_ERROR;
            }
            status = c.U_ZERO_ERROR;
            dynTrans = c.fts5_utrans_openU(dyn_rules_u16.ptr, -1, c.UTRANS_FORWARD, null, 0, null, &status);
            if (c.U_FAILURE(status) or dynTrans == null) {
                return c.SQLITE_ERROR;
            }
            pBreakIterator = dynBreak.?;
            pTransliterator = dynTrans.?;
        }
    }

    var status: c.UErrorCode = c.U_ZERO_ERROR;
    c.fts5_ubrk_setText(pBreakIterator, utf16_text_buffer.ptr, @intCast(utf16_pos), &status);
    if (c.U_FAILURE(status)) return c.SQLITE_ERROR;

    var transBuf = try allocator.alloc(c.UChar, 2048);
    defer allocator.free(transBuf);

    var destBuf = try allocator.alloc(u8, 4096);
    defer allocator.free(destBuf);

    var token_start = c.fts5_ubrk_first(pBreakIterator);
    while (true) {
        const token_end = c.fts5_ubrk_next(pBreakIterator);
        if (token_end == c.UBRK_DONE) break;

        if (token_start < 0 or token_end < 0 or @as(usize, @intCast(token_start)) >= utf16_pos or @as(usize, @intCast(token_end)) > utf16_pos) {
            token_start = token_end;
            continue;
        }

        const word_status = c.fts5_ubrk_getRuleStatus(pBreakIterator);
        if (word_status >= c.UBRK_WORD_NONE and word_status < c.UBRK_WORD_NONE_LIMIT) {
            token_start = token_end;
            continue;
        }

        const iStartByte = byte_offset_map[@intCast(token_start)];
        const iEndByte = byte_offset_map[@intCast(token_end)];
        const nTokenByte = iEndByte - iStartByte;
        if (nTokenByte <= 0) {
            token_start = token_end;
            continue;
        }

        const nSrc: usize = @intCast(token_end - token_start);
        if (nSrc == 0) {
            token_start = token_end;
            continue;
        }

        const reqBufSize = nSrc * 6 + 2048;
        if (transBuf.len < reqBufSize) {
            transBuf = try allocator.realloc(transBuf, reqBufSize);
        }

        const copyLen = @min(nSrc, transBuf.len - 1);
        const start_idx: usize = @intCast(token_start);
        @memcpy(transBuf[0..copyLen], utf16_text_buffer[start_idx .. start_idx + copyLen]);
        transBuf[copyLen] = 0;

        status = c.U_ZERO_ERROR;
        var limit: i32 = @intCast(copyLen);
        var outLen: i32 = @intCast(copyLen);
        c.fts5_utrans_transUChars(pTransliterator, transBuf.ptr, &outLen, @intCast(transBuf.len), 0, &limit, &status);
        if (c.U_FAILURE(status)) {
            token_start = token_end;
            continue;
        }

        const validOutLen: usize = @intCast(@max(0, outLen));

        const reqDestSize = validOutLen * 8 + 4096;
        if (destBuf.len < reqDestSize) {
            destBuf = try allocator.realloc(destBuf, reqDestSize);
        }

        var utf8Len: i32 = 0;
        status = c.U_ZERO_ERROR;
        _ = c.fts5_u_strToUTF8WithSub(destBuf.ptr, @intCast(destBuf.len), &utf8Len, transBuf.ptr, @intCast(validOutLen), 0xFFFD, null, &status);

        if (status == c.U_BUFFER_OVERFLOW_ERROR or (c.U_FAILURE(status) and utf8Len > @as(i32, @intCast(destBuf.len)))) {
            const newDestSize: usize = @intCast(utf8Len + 64);
            destBuf = try allocator.realloc(destBuf, newDestSize);
            utf8Len = 0;
            status = c.U_ZERO_ERROR;
            _ = c.fts5_u_strToUTF8WithSub(destBuf.ptr, @intCast(destBuf.len), &utf8Len, transBuf.ptr, @intCast(validOutLen), 0xFFFD, null, &status);
        }

        if (!c.U_FAILURE(status) and utf8Len > 0) {
            const rc = xToken(pCtx, 0, destBuf.ptr, utf8Len, iStartByte, iEndByte);
            if (rc != c.SQLITE_OK) {
                return rc;
            }
        }

        token_start = token_end;
    }

    return c.SQLITE_OK;
}

test "utf8ToUtf16Alloc memory safety" {
    const testing_allocator = std.testing.allocator;

    const u16_empty = try utf8ToUtf16Alloc(testing_allocator, "");
    defer testing_allocator.free(u16_empty);
    try std.testing.expectEqual(@as(usize, 0), u16_empty.len);

    const u16_hello = try utf8ToUtf16Alloc(testing_allocator, "hello");
    defer testing_allocator.free(u16_hello);
    try std.testing.expectEqual(@as(usize, 5), u16_hello.len);
}

test "IcuTokenizer creation & destruction memory safety" {
    const testing_allocator = std.testing.allocator;

    const tok = try IcuTokenizer.create(testing_allocator, "ja");
    defer tok.destroy(testing_allocator);

    try std.testing.expect(tok.pBreakIterator != null);
    try std.testing.expect(tok.pTransliterator != null);
}

fn dummyTokenCallback(
    pCtx: ?*anyopaque,
    flags: c_int,
    pToken: [*c]const u8,
    nToken: c_int,
    iStart: c_int,
    iEnd: c_int,
) callconv(.c) c_int {
    _ = pCtx;
    _ = flags;
    _ = pToken;
    _ = nToken;
    _ = iStart;
    _ = iEnd;
    return c.SQLITE_OK;
}

test "tokenizeText memory safety and override_locale" {
    const testing_allocator = std.testing.allocator;

    const tok = try IcuTokenizer.create(testing_allocator, "");
    defer tok.destroy(testing_allocator);

    const text = "日本語のテスト and English text";
    const rc = try tokenizeText(testing_allocator, tok, text, "ja", null, dummyTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);
}

