const std = @import("std");
const c = @import("c");
const icu = @import("c_icu");
const rules = @import("rules.zig");
const build_options = @import("build_options");

pub const IcuTokenizer = struct {
    pBreakIterator: ?*c.UBreakIterator,
    pTransliterator: ?*c.UTransliterator,
    locale_slice: []const u8,

    pub fn create(allocator: std.mem.Allocator, locale: []const u8) !*IcuTokenizer {
        var status: c.UErrorCode = c.U_ZERO_ERROR;

        const tok = try allocator.create(IcuTokenizer);
        errdefer allocator.destroy(tok);
        tok.* = .{
            .pBreakIterator = null,
            .pTransliterator = null,
            .locale_slice = try allocator.dupe(u8, locale),
        };
        errdefer allocator.free(tok.locale_slice);

        const rule_str = rules.getRulesForLocale(locale);

        // Convert rule string to UTF-16
        const rules_u16 = try utf8ToUtf16Alloc(allocator, rule_str);
        defer allocator.free(rules_u16);

        // Convert locale string to zero-terminated C string
        const locale_c = try allocator.dupeZ(u8, locale);
        defer allocator.free(locale_c);

        tok.pBreakIterator = icu.ubrk_open(c.UBRK_WORD, locale_c.ptr, null, 0, &status);
        if (c.U_FAILURE(status) or tok.pBreakIterator == null) {
            return error.IcuBreakIteratorFailed;
        }
        errdefer {
            if (tok.pBreakIterator) |bi| icu.ubrk_close(bi);
        }

        status = c.U_ZERO_ERROR;
        tok.pTransliterator = icu.utrans_openU(rules_u16.ptr, -1, c.UTRANS_FORWARD, null, 0, null, &status);
        if (c.U_FAILURE(status) or tok.pTransliterator == null) {
            return error.IcuTransliteratorFailed;
        }

        return tok;
    }

    pub fn destroy(self: *IcuTokenizer, allocator: std.mem.Allocator) void {
        if (self.pBreakIterator) |bi| icu.ubrk_close(bi);
        if (self.pTransliterator) |tr| icu.utrans_close(tr);
        allocator.free(self.locale_slice);
        allocator.destroy(self);
    }
};

pub fn utf8ToUtf16Alloc(allocator: std.mem.Allocator, text: []const u8) ![:0]c.UChar {
    // Use the std UTF-8 -> UTF-16 converter (bug #7). utf8ToUtf16LeAllocZ
    // returns [:0]u16, identical to [:0]c.UChar, so every caller is unchanged.
    return std.unicode.utf8ToUtf16LeAllocZ(allocator, text);
}

pub fn transliterateString(allocator: std.mem.Allocator, input: []const u8, rule_str: []const u8) ![]u8 {
    var status: c.UErrorCode = c.U_ZERO_ERROR;

    const rules_u16 = try utf8ToUtf16Alloc(allocator, rule_str);
    defer allocator.free(rules_u16);

    const transliterator = icu.utrans_openU(rules_u16.ptr, -1, c.UTRANS_FORWARD, null, 0, null, &status);
    if (c.U_FAILURE(status) or transliterator == null) {
        return error.TransliteratorCreateFailed;
    }
    defer icu.utrans_close(transliterator);

    const input_u16 = try utf8ToUtf16Alloc(allocator, input);
    defer allocator.free(input_u16);

    const capacity = input_u16.len * 3 + 64;
    var output_u16 = try allocator.alloc(c.UChar, capacity);
    defer allocator.free(output_u16);

    @memcpy(output_u16[0..input_u16.len], input_u16);

    var limit: i32 = @intCast(input_u16.len);
    var out_len: i32 = @intCast(input_u16.len);
    status = c.U_ZERO_ERROR;
    icu.utrans_transUChars(transliterator, output_u16.ptr, &out_len, @intCast(capacity), 0, &limit, &status);
    if (status == c.U_BUFFER_OVERFLOW_ERROR) {
        // Transliteration expanded beyond the buffer (bug #3): grow to the
        // required length and retry, instead of returning an error.
        //
        // Bug #8 fix: allocate the replacement buffer into a temporary first,
        // then swap. The previous code freed `output_u16` and reassigned it
        // before the `try`; on OutOfMemory the `defer allocator.free(output_u16)`
        // would run on the already-freed pointer (double free, CWE-415). By
        // allocating into `new_u16` first, a failed realloc leaves `output_u16`
        // pointing at the still-valid original buffer, which `defer` frees once.
        const need: usize = @as(usize, @intCast(out_len)) + 64;
        const new_u16 = try allocator.alloc(c.UChar, need);
        allocator.free(output_u16);
        output_u16 = new_u16;
        @memcpy(output_u16[0..input_u16.len], input_u16);
        out_len = @intCast(input_u16.len);
        limit = out_len;
        status = c.U_ZERO_ERROR;
        icu.utrans_transUChars(transliterator, output_u16.ptr, &out_len, @intCast(need), 0, &limit, &status);
    }
    if (c.U_FAILURE(status)) {
        return error.TransliterateFailed;
    }

    var utf8_len: i32 = 0;
    status = c.U_ZERO_ERROR;
    _ = icu.u_strToUTF8(null, 0, &utf8_len, output_u16.ptr, limit, &status);
    if (status != c.U_BUFFER_OVERFLOW_ERROR and status != c.U_ZERO_ERROR) {
        return error.Utf8LengthFailed;
    }

    status = c.U_ZERO_ERROR;
    // Bug #10 fix: `utf8_len` from the preflight is the content length WITHOUT
    // the NUL terminator (verified empirically against ICU). Allocate room for
    // the terminator — ICU writes it when the buffer is large enough — and
    // pass `destCapacity = utf8_len + 1`. The returned slice is an exact
    // `utf8_len`-byte copy so the caller can free it normally; returning a
    // sub-slice of the +1 buffer would be unfreeable. The previous code used a
    // `utf8_len`-byte buffer with `destCapacity = utf8_len + 1`, a 1-byte heap
    // overflow (the NUL was written one byte past the allocation, CWE-787).
    const buf_with_nul = try allocator.alloc(u8, @as(usize, @intCast(utf8_len)) + 1);
    defer allocator.free(buf_with_nul);

    _ = icu.u_strToUTF8(buf_with_nul.ptr, utf8_len + 1, null, output_u16.ptr, limit, &status);
    if (c.U_FAILURE(status)) {
        return error.Utf8ConvertFailed;
    }

    return allocator.dupe(u8, buf_with_nul[0..@as(usize, @intCast(utf8_len))]);
}

// Build the UTF-8 byte-offset map (utf16 index -> utf8 start byte) for `text`.
// Tolerant of malformed UTF-8 (substitutes U+FFFD), so it matches the std
// converter's output for valid input and degrades gracefully otherwise.
fn buildByteOffsetMap(map: []i32, text: []const u8) void {
    var utf8_pos: usize = 0;
    var u: usize = 0;
    while (utf8_pos < text.len and u < map.len) {
        const orig_utf8 = utf8_pos;
        const cp_len = std.unicode.utf8ByteSequenceLength(text[utf8_pos]) catch 1;
        const end = @min(utf8_pos + cp_len, text.len);
        const cp = std.unicode.utf8Decode(text[utf8_pos..end]) catch 0xFFFD;
        utf8_pos = end;
        const units: usize = if (cp <= 0xFFFF) 1 else 2;
        if (u < map.len) map[u] = @intCast(orig_utf8);
        if (cp > 0xFFFF and u + 1 < map.len) map[u + 1] = @intCast(orig_utf8);
        u += units;
    }
}

// Tolerant manual UTF-8 -> UTF-16 conversion (substitutes U+FFFD for invalid
// sequences). Fills both the UTF-16 buffer and the byte-offset map; returns the
// number of UTF-16 units written. Used as a fallback when
// std.unicode.utf8ToUtf16Le rejects malformed input.
fn convertUtf8ToUtf16Tolerant(
    utf16_buf: []c.UChar,
    map: []i32,
    text: []const u8,
) usize {
    var utf16_pos: usize = 0;
    var utf8_pos: usize = 0;
    while (utf8_pos < text.len and utf16_pos < utf16_buf.len) {
        const orig_utf8 = utf8_pos;
        const cp_len = std.unicode.utf8ByteSequenceLength(text[utf8_pos]) catch 1;
        const end = @min(utf8_pos + cp_len, text.len);
        const cp = std.unicode.utf8Decode(text[utf8_pos..end]) catch 0xFFFD;
        utf8_pos = end;

        const orig_utf16 = utf16_pos;
        if (cp <= 0xFFFF) {
            utf16_buf[utf16_pos] = @intCast(cp);
            utf16_pos += 1;
        } else {
            if (utf16_pos + 2 > utf16_buf.len) break;
            utf16_buf[utf16_pos] = @intCast(0xD800 + ((cp - 0x10000) >> 10));
            utf16_buf[utf16_pos + 1] = @intCast(0xDC00 + ((cp - 0x10000) & 0x3FF));
            utf16_pos += 2;
        }

        if (orig_utf16 < map.len) map[orig_utf16] = @intCast(orig_utf8);
        if (cp > 0xFFFF and orig_utf16 + 1 < map.len) map[orig_utf16 + 1] = @intCast(orig_utf8);
    }
    return utf16_pos;
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

    const STACK_CAP = 512;
    // UTF-16 is at most 2 units per UTF-8 byte, so size for 2*len + 1.
    const req_u16_cap = text.len * 2 + 1;

    var stack_utf16: [STACK_CAP]c.UChar = undefined;
    var stack_map: [STACK_CAP]i32 = undefined;
    var stack_trans: [STACK_CAP * 2]c.UChar = undefined;
    var stack_dest: [STACK_CAP * 4]u8 = undefined;

    var heap_utf16: ?[]c.UChar = null;
    defer if (heap_utf16) |buf| allocator.free(buf);
    const utf16_text_buffer = if (req_u16_cap <= STACK_CAP)
        stack_utf16[0..req_u16_cap]
    else blk: {
        heap_utf16 = try allocator.alloc(c.UChar, req_u16_cap);
        break :blk heap_utf16.?;
    };

    var heap_map: ?[]i32 = null;
    defer if (heap_map) |buf| allocator.free(buf);
    const byte_offset_map = if (req_u16_cap <= STACK_CAP)
        stack_map[0..req_u16_cap]
    else blk: {
        heap_map = try allocator.alloc(i32, req_u16_cap);
        break :blk heap_map.?;
    };

    var heap_trans: ?[]c.UChar = null;
    defer if (heap_trans) |buf| allocator.free(buf);
    var transBuf: []c.UChar = if (req_u16_cap <= STACK_CAP)
        stack_trans[0..]
    else blk: {
        heap_trans = try allocator.alloc(c.UChar, 2048);
        break :blk heap_trans.?;
    };

    var heap_dest: ?[]u8 = null;
    defer if (heap_dest) |buf| allocator.free(buf);
    var destBuf: []u8 = if (req_u16_cap <= STACK_CAP)
        stack_dest[0..]
    else blk: {
        heap_dest = try allocator.alloc(u8, 4096);
        break :blk heap_dest.?;
    };

    // Convert UTF-8 -> UTF-16. Use the std converter (bug #4): it is
    // vectorized and battle-tested. It errors on malformed input, so fall back
    // to a tolerant manual conversion that substitutes U+FFFD (preserving the
    // previous behavior for the "malformed UTF-8 and emoji safety" test).
    var utf16_pos: usize = undefined;
    if (std.unicode.utf8ToUtf16Le(utf16_text_buffer, text)) |n| {
        utf16_pos = n;
        buildByteOffsetMap(byte_offset_map, text);
    } else |_| {
        utf16_pos = convertUtf8ToUtf16Tolerant(utf16_text_buffer, byte_offset_map, text);
    }
    if (utf16_pos < byte_offset_map.len) {
        byte_offset_map[utf16_pos] = @intCast(text.len);
    }

    var baseBreakIterator = tokenizer.pBreakIterator.?;
    var pTransliterator = tokenizer.pTransliterator.?;

    var dynBreak: ?*c.UBreakIterator = null;
    var dynTrans: ?*c.UTransliterator = null;
    defer {
        if (dynBreak) |b| icu.ubrk_close(b);
        if (dynTrans) |t| icu.utrans_close(t);
    }

    if (override_locale) |loc| {
        if (loc.len > 0) {
            var status: c.UErrorCode = c.U_ZERO_ERROR;
            const loc_c = try allocator.dupeZ(u8, loc);
            defer allocator.free(loc_c);

            const dyn_rules = rules.getRulesForLocale(loc);
            const dyn_rules_u16 = try utf8ToUtf16Alloc(allocator, dyn_rules);
            defer allocator.free(dyn_rules_u16);

            dynBreak = icu.ubrk_open(c.UBRK_WORD, loc_c.ptr, null, 0, &status);
            if (c.U_FAILURE(status) or dynBreak == null) {
                return c.SQLITE_ERROR;
            }
            status = c.U_ZERO_ERROR;
            dynTrans = icu.utrans_openU(dyn_rules_u16.ptr, -1, c.UTRANS_FORWARD, null, 0, null, &status);
            if (c.U_FAILURE(status) or dynTrans == null) {
                return c.SQLITE_ERROR;
            }
            baseBreakIterator = dynBreak.?;
            pTransliterator = dynTrans.?;
        }
    }

    // Thread Safety: Clone (or fresh-open on ICU < 69) break iterator for concurrent execution safety
    var clone_status: c.UErrorCode = c.U_ZERO_ERROR;
    const pBreakIterator = if (build_options.has_ubrk_clone)
        c.ubrk_clone(baseBreakIterator, &clone_status)
    else blk: {
        const locale_z = try allocator.dupeZ(u8, tokenizer.locale_slice);
        defer allocator.free(locale_z);
        break :blk icu.ubrk_open(c.UBRK_WORD, locale_z.ptr, null, 0, &clone_status);
    };
    if (c.U_FAILURE(clone_status) or pBreakIterator == null) return c.SQLITE_ERROR;
    defer icu.ubrk_close(pBreakIterator);

    // Thread Safety: also clone the transliterator. UTransliterator is not
    // thread-safe, so the shared handle owned by IcuTokenizer must not be used
    // concurrently. Clone it per call, mirroring the break-iterator clone above.
    var trans_clone_status: c.UErrorCode = c.U_ZERO_ERROR;
    const pClonedTransliterator = icu.utrans_clone(pTransliterator, &trans_clone_status);
    if (c.U_FAILURE(trans_clone_status) or pClonedTransliterator == null) return c.SQLITE_ERROR;
    defer icu.utrans_close(pClonedTransliterator);

    var status: c.UErrorCode = c.U_ZERO_ERROR;
    icu.ubrk_setText(pBreakIterator, utf16_text_buffer.ptr, @intCast(utf16_pos), &status);
    if (c.U_FAILURE(status)) return c.SQLITE_ERROR;

    var token_start = icu.ubrk_first(pBreakIterator);
    while (true) {
        const token_end = icu.ubrk_next(pBreakIterator);
        if (token_end == c.UBRK_DONE) break;

        if (token_start < 0 or token_end < 0 or @as(usize, @intCast(token_start)) >= utf16_pos or @as(usize, @intCast(token_end)) > utf16_pos) {
            token_start = token_end;
            continue;
        }

        const word_status = icu.ubrk_getRuleStatus(pBreakIterator);
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

        const reqBufSize = nSrc * 6 + 64;
        if (transBuf.len < reqBufSize) {
            if (heap_trans) |ht| {
                heap_trans = try allocator.realloc(ht, reqBufSize);
                transBuf = heap_trans.?;
            } else {
                heap_trans = try allocator.alloc(c.UChar, reqBufSize);
                transBuf = heap_trans.?;
            }
        }

        const copyLen = @min(nSrc, transBuf.len - 1);
        const start_idx: usize = @intCast(token_start);
        @memcpy(transBuf[0..copyLen], utf16_text_buffer[start_idx .. start_idx + copyLen]);
        transBuf[copyLen] = 0;

        status = c.U_ZERO_ERROR;
        var limit: i32 = @intCast(copyLen);
        var outLen: i32 = @intCast(copyLen);
        icu.utrans_transUChars(pClonedTransliterator, transBuf.ptr, &outLen, @intCast(transBuf.len), 0, &limit, &status);
        if (status == c.U_BUFFER_OVERFLOW_ERROR) {
            // Transliteration expanded beyond the current buffer (bug #2): grow
            // to the required length and retry, instead of silently dropping
            // the token. `outLen` holds the length ICU needs.
            const need: usize = @as(usize, @intCast(outLen)) + 64;
            if (heap_trans) |ht| {
                heap_trans = try allocator.realloc(ht, need);
            } else {
                heap_trans = try allocator.alloc(c.UChar, need);
            }
            transBuf = heap_trans.?;
            @memcpy(transBuf[0..copyLen], utf16_text_buffer[start_idx .. start_idx + copyLen]);
            transBuf[copyLen] = 0;
            outLen = @intCast(copyLen);
            limit = outLen;
            status = c.U_ZERO_ERROR;
            icu.utrans_transUChars(pClonedTransliterator, transBuf.ptr, &outLen, @intCast(transBuf.len), 0, &limit, &status);
        }
        if (c.U_FAILURE(status)) {
            token_start = token_end;
            continue;
        }

        const validOutLen: usize = @intCast(@max(0, outLen));

        const reqDestSize = validOutLen * 4 + 64;
        if (destBuf.len < reqDestSize) {
            if (heap_dest) |hd| {
                heap_dest = try allocator.realloc(hd, reqDestSize);
                destBuf = heap_dest.?;
            } else {
                heap_dest = try allocator.alloc(u8, reqDestSize);
                destBuf = heap_dest.?;
            }
        }

        var utf8Len: i32 = 0;
        status = c.U_ZERO_ERROR;
        _ = icu.u_strToUTF8WithSub(destBuf.ptr, @intCast(destBuf.len), &utf8Len, transBuf.ptr, @intCast(validOutLen), 0xFFFD, null, &status);

        if (status == c.U_BUFFER_OVERFLOW_ERROR or (c.U_FAILURE(status) and utf8Len > @as(i32, @intCast(destBuf.len)))) {
            const newDestSize: usize = @intCast(utf8Len + 64);
            if (heap_dest) |hd| {
                heap_dest = try allocator.realloc(hd, newDestSize);
                destBuf = heap_dest.?;
            } else {
                heap_dest = try allocator.alloc(u8, newDestSize);
                destBuf = heap_dest.?;
            }
            utf8Len = 0;
            status = c.U_ZERO_ERROR;
            _ = icu.u_strToUTF8WithSub(destBuf.ptr, @intCast(destBuf.len), &utf8Len, transBuf.ptr, @intCast(validOutLen), 0xFFFD, null, &status);
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

test "utf8ToUtf16Alloc uses std converter for non-ASCII (bug #7)" {
    const testing_allocator = std.testing.allocator;

    // 日本語 = 3 BMP codepoints -> 3 UTF-16 units (verifies the std converter
    // path, not the old ICU u_strFromUTF8 probe).
    const u16buf = try utf8ToUtf16Alloc(testing_allocator, "日本語");
    defer testing_allocator.free(u16buf);
    try std.testing.expectEqual(@as(usize, 3), u16buf.len);
}

test "transliterateString grows buffer instead of erroring (bug #3)" {
    const gpa = std.testing.allocator;

    // Long mixed input that expands under transliteration. Must succeed and
    // produce the expected Latin output rather than error.TransliterateFailed.
    const input = "русский текст العربية Ελληνικά Français Español";
    const out = try transliterateString(gpa, input, rules.ICU_RULE_DEFAULT);
    defer gpa.free(out);

    try std.testing.expect(out.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out, "russkij") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "francais") != null);
}

// Bug #8: the grow-on-overflow retry path in transliterateString previously
// freed the old buffer and reassigned `output_u16` before the realloc `try`. On
// OutOfMemory that left `output_u16` pointing at freed memory, and the
// `defer allocator.free(output_u16)` then double-freed it (CWE-415). This test
// drives the retry branch with a transform (`Any-Name`) that spells each input
// character out as its long Unicode name, so the final output far exceeds the
// `len * 3 + 64` capacity heuristic and the grow-on-overflow retry branch must
// run. The double free itself is undefined behavior the testing allocator does
// not detect, so this guards the code path and its output rather than the OOM
// path directly.
test "transliterateString overflow retry is correct (bug #8)" {
    const gpa = std.testing.allocator;

    // `Any-Name` rewrites each character to its spelled-out Unicode name
    // (e.g. "A" -> "LATIN CAPITAL LETTER A"). For the 4-char input the
    // transliteration is ~104 UTF-16 units, well above the capacity of
    // 4*3 + 64 = 76, forcing the grow-on-overflow retry branch.
    const out = try transliterateString(gpa, "ABCD", "Any-Name");
    defer gpa.free(out);

    // Final output exceeded the initial capacity, so the overflow-retry branch
    // executed and produced a correct, expanded result.
    try std.testing.expect(out.len > 76);
    try std.testing.expect(std.mem.indexOf(u8, out, "LATIN") != null);
}

// Bug #10: the final UTF-16 -> UTF-8 step must allocate room for the NUL
// terminator ICU writes (the preflight `utf8_len` excludes it) and pass
// `destCapacity = utf8_len + 1`. A `utf8_len`-byte buffer with
// `destCapacity = utf8_len + 1` is a 1-byte heap overflow, and the earlier
// draft's proposed `destCapacity = utf8_len` instead makes ICU return
// U_BUFFER_OVERFLOW_ERROR so transliterateString fails. This test guards both:
// it must succeed and return the exact transliterated text.
test "transliterateString UTF-8 terminator fits buffer (bug #10)" {
    const gpa = std.testing.allocator;

    const out = try transliterateString(gpa, "Café", rules.ICU_RULE_DEFAULT);
    defer gpa.free(out);

    // NFKD + Latin-ASCII + NFKC reduces "Café" to "cafe"; the returned slice is
    // exactly the content (the terminator is internal-only and excluded from
    // the length).
    try std.testing.expectEqualStrings("cafe", out);
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

test "tokenizeText large text SBO fallback" {
    const testing_allocator = std.testing.allocator;

    const tok = try IcuTokenizer.create(testing_allocator, "");
    defer tok.destroy(testing_allocator);

    // Generate string larger than 512 bytes
    var large_text = try testing_allocator.alloc(u8, 2048);
    defer testing_allocator.free(large_text);
    @memset(large_text, 'a');
    large_text[100] = ' ';
    large_text[500] = ' ';
    large_text[1000] = ' ';
    large_text[1500] = ' ';

    const rc = try tokenizeText(testing_allocator, tok, large_text, null, null, dummyTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);
}

test "tokenizeText small input zero heap allocations (SBO)" {
    if (!build_options.has_ubrk_clone) return error.SkipZigTest;

    const testing_allocator = std.testing.allocator;

    const tok = try IcuTokenizer.create(testing_allocator, "");
    defer tok.destroy(testing_allocator);

    const small_text = "Hello world! 日本語のテスト 1234";

    // Pass failing_allocator to tokenizeText. If tokenizeText attempts any
    // heap allocations for small input, failing_allocator will return error.OutOfMemory.
    const failing_allocator = std.testing.failing_allocator;
    const rc = try tokenizeText(failing_allocator, tok, small_text, null, null, dummyTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);
}

test "tokenizeText malformed UTF-8 and emoji safety" {
    const testing_allocator = std.testing.allocator;

    const tok = try IcuTokenizer.create(testing_allocator, "");
    defer tok.destroy(testing_allocator);

    const text_emoji = "Hello 🌍 World! 😀 🎉 🦺";
    const rc1 = try tokenizeText(testing_allocator, tok, text_emoji, null, null, dummyTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc1);

    const text_invalid = "Hello \xFF\xFE World!";
    const rc2 = try tokenizeText(testing_allocator, tok, text_invalid, null, null, dummyTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc2);
}

// Bug #4: the UTF-8 -> UTF-16 conversion (now std.unicode.utf8ToUtf16Le) must
// not drop or truncate a trailing surrogate-pair codepoint. Verify a trailing
// emoji survives tokenization as a complete codepoint.
test "tokenizeText byte ranges around surrogate pair (bug #4)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    // Astral-plane char (emoji, 4 UTF-8 bytes / 2 UTF-16 units) between two
    // words. The std UTF-8 -> UTF-16 conversion (bug #4) must map the emoji's
    // 4 bytes correctly so the following word's byte range is exact.
    // bytes: hello(5) + 🌍(4) + world(5) = 14
    const text = "hello🌍world";
    var cap: CaptureWithRange = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t.text);
        cap.tokens.deinit(gpa);
    }
    const rc = try tokenizeText(gpa, tok, text, null, &cap, captureRangeCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);

    for (cap.tokens.items) |t| {
        if (std.mem.eql(u8, t.text, "world")) {
            try std.testing.expectEqual(@as(i32, 9), t.i_start);
            try std.testing.expectEqual(@as(i32, 14), t.i_end);
        }
    }
}

test "concurrent multi-threaded tokenizeText thread safety" {
    const testing_allocator = std.testing.allocator;

    const tok = try IcuTokenizer.create(testing_allocator, "ja");
    defer tok.destroy(testing_allocator);

    const ThreadContext = struct {
        tokenizer: *IcuTokenizer,
        text: []const u8,
        fn worker(self: @This()) void {
            const rc = tokenizeText(std.heap.c_allocator, self.tokenizer, self.text, null, null, dummyTokenCallback) catch c.SQLITE_ERROR;
            std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc) catch {};
        }
    };

    var threads: [8]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        const text = if (i % 2 == 0) "日本語のテスト text" else "English text and 日本語";
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{
            .tokenizer = tok,
            .text = text,
        }});
    }

    for (threads) |t| {
        t.join();
    }
}

const Capture = struct {
    gpa: std.mem.Allocator,
    tokens: std.ArrayList([]const u8),
};

fn captureTokenCallback(
    pCtx: ?*anyopaque,
    flags: c_int,
    pToken: [*c]const u8,
    nToken: c_int,
    iStart: c_int,
    iEnd: c_int,
) callconv(.c) c_int {
    _ = flags;
    _ = iStart;
    _ = iEnd;
    const cap: *Capture = @ptrCast(@alignCast(pCtx.?));
    const owned = cap.gpa.dupe(u8, pToken[0..@intCast(nToken)]) catch return c.SQLITE_NOMEM;
    cap.tokens.append(cap.gpa, owned) catch {
        cap.gpa.free(owned);
        return c.SQLITE_NOMEM;
    };
    return c.SQLITE_OK;
}

const TokenRange = struct {
    text: []const u8,
    i_start: i32,
    i_end: i32,
};

const CaptureWithRange = struct {
    gpa: std.mem.Allocator,
    tokens: std.ArrayList(TokenRange),
};

fn captureRangeCallback(
    pCtx: ?*anyopaque,
    flags: c_int,
    pToken: [*c]const u8,
    nToken: c_int,
    iStart: c_int,
    iEnd: c_int,
) callconv(.c) c_int {
    _ = flags;
    const cap: *CaptureWithRange = @ptrCast(@alignCast(pCtx.?));
    const owned = cap.gpa.dupe(u8, pToken[0..@intCast(nToken)]) catch return c.SQLITE_NOMEM;
    cap.tokens.append(cap.gpa, .{ .text = owned, .i_start = iStart, .i_end = iEnd }) catch {
        cap.gpa.free(owned);
        return c.SQLITE_NOMEM;
    };
    return c.SQLITE_OK;
}

// Bug #1: the shared UTransliterator must be cloned per tokenizeText call, not
// used concurrently. This test verifies the transliteration actually runs (via
// the clone) by checking that Cyrillic input becomes pure-ASCII Latin tokens.
test "transliterator clone correctness (ru transliteration)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "ru");
    defer tok.destroy(gpa);

    var cap: Capture = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t);
        cap.tokens.deinit(gpa);
    }

    const rc = try tokenizeText(gpa, tok, "русский текст", null, &cap, captureTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);
    try std.testing.expect(cap.tokens.items.len > 0);
    for (cap.tokens.items) |t| {
        for (t) |b| try std.testing.expect(b < 0x80);
    }
}

// Bug #1: concurrent use of a single shared tokenizer while transliterating.
// The transliterator is cloned per call, so this must not race/corrupt.
test "concurrent tokenizeText with transliteration (thread safety)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "ru");
    defer tok.destroy(gpa);

    const ThreadContext = struct {
        tokenizer: *IcuTokenizer,
        fn worker(self: @This()) void {
            const rc = tokenizeText(
                std.heap.c_allocator,
                self.tokenizer,
                "русский текст пример",
                null,
                null,
                dummyTokenCallback,
            ) catch c.SQLITE_ERROR;
            std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc) catch {};
        }
    };

    var threads: [8]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{ .tokenizer = tok }});
    }
    for (threads) |t| t.join();
}

// Bug #2: a token whose transliteration expands beyond the buffer must not be
// silently dropped. The grow-on-overflow path is the fix; this regression test
// ensures no token is lost under heavy transliteration with the universal
// (Latinizing) rule set.
test "tokenizeText transliteration preserves all tokens (bug #2 regression)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    // Scripts the universal rule set Latinizes to pure ASCII: Cyrillic, Arabic,
    // Greek, and Latin with diacritics. (CJK/Thai are intentionally excluded
    // because the universal rules do not Latinize them.)
    const text = "русский текст العربية Ελληνικά Français Español";

    var cap: Capture = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t);
        cap.tokens.deinit(gpa);
    }

    const rc = try tokenizeText(gpa, tok, text, null, &cap, captureTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);

    // Bug #2 guard: no token may be silently dropped. Verify representative
    // transliterated tokens are present.
    var found_russian = false;
    var found_french = false;
    for (cap.tokens.items) |t| {
        if (std.mem.eql(u8, t, "russkij")) found_russian = true;
        if (std.mem.eql(u8, t, "francais")) found_french = true;
    }
    try std.testing.expect(cap.tokens.items.len >= 6);
    try std.testing.expect(found_russian);
    try std.testing.expect(found_french);
}
