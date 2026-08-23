const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");
const icu = @import("c_icu");
const rules = @import("rules.zig");
const build_options = @import("build_options");

const has_ubrk_clone = if (builtin.os.tag.isDarwin()) true else c.U_ICU_VERSION_MAJOR_NUM >= 69;

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

        // Bug #16: reject locales ICU cannot resolve (e.g. typo'd "xx_YY"),
        // which ubrk_open silently falls back to root for.
        if (!isValidLocaleLanguage(locale_c.ptr)) return error.IcuInvalidLocale;

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
    if (std.mem.indexOf(u8, rule_str, "Russian-Latin/BGN") != null) {
        premapRussianYat(output_u16[0..input_u16.len]);
    }

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
        if (std.mem.indexOf(u8, rule_str, "Russian-Latin/BGN") != null) {
            premapRussianYat(output_u16[0..input_u16.len]);
        }
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

    // Bug #18: strip Arabic-Latin/Hebrew-Latin modifier letters (U+02BF/
    // U+02BB/U+2019) so the returned string is pure ASCII.
    const ar_he_latin = std.mem.indexOf(u8, rule_str, "Arabic-Latin") != null or
        std.mem.indexOf(u8, rule_str, "Hebrew-Latin") != null;
    const final_len: i32 = if (ar_he_latin)
        stripTranslitMarks(buf_with_nul[0..@as(usize, @intCast(utf8_len))])
    else
        @intCast(utf8_len);

    return allocator.dupe(u8, buf_with_nul[0..@as(usize, @intCast(final_len))]);
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

// Bug #14: ICU's Russian-Latin/BGN maps Cyrillic й/Й (U+0439/U+0419) to 'i',
// colliding distinct words (мой/мои both become "moi"). The published
// BGN/PCGN romanization maps й to 'y'. Pre-map it in the UTF-16 domain before
// the transliteration pipeline runs; the replacement is 1:1 in UTF-16 units,
// so the position map remains exact.
fn premapRussianYat(u16buf: []c.UChar) void {
    for (u16buf) |*u| {
        if (u.* == 0x0439 or u.* == 0x0419) u.* = 'y';
    }
}

// Bug #15: every transliteration chain preserves existing whitespace 1:1,
// so original whitespace positions are exact anchors between the original
// and the normalized text. Verified by probe: NFKD maps NBSP (U+00A0) and all
// of U+2000..U+200A, U+202F, U+205F, U+3000 to U+0020, while ZWSP (U+200B),
// LS (U+2028), PS (U+2029) and U+1680 do not decompose (they are never
// anchors). Bug #19 exception: NFKD can also CREATE whitespace that the
// source never had (U+FDFA expands into text containing spaces); those
// phantom spaces are handled by end-pairing in tokenizeText.
fn isSpaceLikeU16(ch: c.UChar) bool {
    return ch == 0x20 or (ch >= 0x09 and ch <= 0x0D) or ch == 0xA0 or
        (ch >= 0x2000 and ch <= 0x200A) or ch == 0x202F or ch == 0x205F or ch == 0x3000;
}

// Fill `pm[ns..ne]` (a normalized-text segment) by round-half-up proportional
// scaling onto the original-text span `[os, oe)`. Used between whitespace
// anchors; a 1:1 segment maps exactly. A degenerate empty original span pins
// to its boundary instead of dividing by zero.
fn fillSegment(pm: []i32, ns: usize, ne: usize, os: usize, oe: usize) void {
    const seg_norm_len = ne - ns;
    if (seg_norm_len == 0) return;
    const seg_orig_len = oe - os;
    if (seg_orig_len == 0) {
        for (ns..ne) |k| pm[k] = @intCast(os);
        return;
    }
    for (ns..ne) |k| {
        const rel = (k - ns) * seg_orig_len;
        pm[k] = @intCast(os + (rel + seg_norm_len / 2) / seg_norm_len);
    }
}

// Bug #16: validate a locale string before handing it to ICU. `ubrk_open`
// reports U_USING_FALLBACK_WARNING for EVERY non-empty locale — even valid
// ones like "ja" or "ru_RU", because word-break data lives in root — so the
// status code cannot distinguish a typo'd locale from a good one (verified by
// probe on ICU 78 and 67.1.0). Instead check that the locale's language is
// either a supported alias (rules.zig) or a language ICU knows about
// (uloc_getAvailable). The universal tokenizer's empty locale is always valid.
fn isValidLocaleLanguage(locale_c: [*:0]const u8) bool {
    const locale = std.mem.span(locale_c);
    if (locale.len == 0) return true;
    if (std.mem.eql(u8, locale, "C") or std.mem.eql(u8, locale, "POSIX")) return true;

    var lang_buf: [16]u8 = undefined;
    var st: c.UErrorCode = c.U_ZERO_ERROR;
    const n = icu.uloc_getLanguage(locale_c, &lang_buf, lang_buf.len, &st);
    if (c.U_FAILURE(st) or n < 0 or @as(usize, @intCast(n)) > lang_buf.len) return false;
    const lang = lang_buf[0..@intCast(n)];

    const aliases = [_][]const u8{ "ja", "jp", "zh", "cn", "th", "ko", "kr", "ar", "ru", "he", "iw", "el", "gr" };
    for (aliases) |a| {
        if (std.mem.eql(u8, lang, a)) return true;
    }

    const count = icu.uloc_countAvailable();
    var i: i32 = 0;
    while (i < count) : (i += 1) {
        if (std.mem.eql(u8, lang, std.mem.span(icu.uloc_getAvailable(i)))) return true;
    }
    return false;
}

// Bug #18: Arabic-Latin emits U+02BF (ʿ) and Hebrew-Latin can emit U+02BB (ʻ)
// and U+2019 (ʼ) modifier letters that Latin-ASCII leaves in place (verified
// on ICU 78 and 67.1.0: Arabic keeps U+02BF; Hebrew output is already ASCII
// on both, but the general case is covered here). Strip them from the token
// text (UTF-8 CA BF, CA BB, E2 80 99) so ar/he tokens are pure ASCII and
// Latin-spelled queries match. Only the token text is compacted — the
// reported byte range still points at the original word. Returns the new
// length of `buf` (<= original).
fn stripTranslitMarks(buf: []u8) i32 {
    var w: usize = 0;
    var i: usize = 0;
    while (i < buf.len) {
        if (i + 1 < buf.len and buf[i] == 0xCA and (buf[i + 1] == 0xBF or buf[i + 1] == 0xBB)) {
            i += 2;
        } else if (i + 2 < buf.len and buf[i] == 0xE2 and buf[i + 1] == 0x80 and buf[i + 2] == 0x99) {
            i += 3;
        } else {
            buf[w] = buf[i];
            w += 1;
            i += 1;
        }
    }
    return @intCast(w);
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
    const req_u16_cap = text.len * 2 + 1;

    var stack_utf16: [STACK_CAP]c.UChar = undefined;
    var stack_map: [STACK_CAP]i32 = undefined;
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

    var heap_dest: ?[]u8 = null;
    defer if (heap_dest) |buf| allocator.free(buf);
    var destBuf: []u8 = if (req_u16_cap <= STACK_CAP)
        stack_dest[0..]
    else blk: {
        heap_dest = try allocator.alloc(u8, 4096);
        break :blk heap_dest.?;
    };

    // Convert UTF-8 -> UTF-16
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

    // Effective locale mirrors the override logic below (non-empty override
    // wins, otherwise the tokenizer's own locale).
    const effective_locale: []const u8 = if (override_locale) |l|
        (if (l.len > 0) l else tokenizer.locale_slice)
    else
        tokenizer.locale_slice;
    const uses_russian_bgn = std.mem.indexOf(u8, rules.getRulesForLocale(effective_locale), "Russian-Latin/BGN") != null;
    const uses_ar_he_latin = std.mem.indexOf(u8, rules.getRulesForLocale(effective_locale), "Arabic-Latin") != null or
        std.mem.indexOf(u8, rules.getRulesForLocale(effective_locale), "Hebrew-Latin") != null;

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

    // Clone break iterator for thread safety
    var clone_status: c.UErrorCode = c.U_ZERO_ERROR;
    const pBreakIterator = if (has_ubrk_clone)
        icu.ubrk_clone(baseBreakIterator, &clone_status)
    else blk: {
        // Bug #17: use the effective (per-call override, when present) locale
        // instead of the tokenizer's own, matching ubrk_clone behavior on
        // newer ICU.
        const locale_z = try allocator.dupeZ(u8, effective_locale);
        defer allocator.free(locale_z);
        break :blk icu.ubrk_open(c.UBRK_WORD, locale_z.ptr, null, 0, &clone_status);
    };
    if (c.U_FAILURE(clone_status) or pBreakIterator == null) return c.SQLITE_ERROR;
    defer icu.ubrk_close(pBreakIterator);

    // Clone transliterator for thread safety
    var trans_clone_status: c.UErrorCode = c.U_ZERO_ERROR;
    const pClonedTransliterator = icu.utrans_clone(pTransliterator, &trans_clone_status);
    if (c.U_FAILURE(trans_clone_status) or pClonedTransliterator == null) return c.SQLITE_ERROR;
    defer icu.utrans_close(pClonedTransliterator);

    // Pre-transliteration: normalize the entire input before word breaking.
    // This prevents UBRK_WORD from fragmenting tokens when transliteration
    // changes script properties (e.g. hiragana+ー is illegal but
    // H->K normalizes to katakana where ー is valid, keeping tokens intact).
    const req_norm_cap = utf16_pos * 3 + 64;
    var stack_norm: [STACK_CAP * 3]c.UChar = undefined;
    var stack_posmap: [STACK_CAP * 3 + 1]i32 = undefined;

    var heap_norm: ?[]c.UChar = null;
    defer if (heap_norm) |buf| allocator.free(buf);
    var heap_posmap: ?[]i32 = null;
    defer if (heap_posmap) |pm| allocator.free(pm);

    var normText: []c.UChar = undefined;
    var position_map: []i32 = undefined;

    {
        const use_stack = req_norm_cap <= STACK_CAP * 3;
        const norm_cap = if (use_stack) STACK_CAP * 3 else req_norm_cap;

        var cur_norm: []c.UChar = if (use_stack)
            stack_norm[0..norm_cap]
        else blk2: {
            heap_norm = try allocator.alloc(c.UChar, norm_cap);
            break :blk2 heap_norm.?;
        };

        @memcpy(cur_norm[0..utf16_pos], utf16_text_buffer[0..utf16_pos]);
        if (uses_russian_bgn) premapRussianYat(cur_norm[0..utf16_pos]);
        cur_norm[utf16_pos] = 0;

        var ts: c.UErrorCode = c.U_ZERO_ERROR;
        var tlimit: i32 = @intCast(utf16_pos);
        var tlen: i32 = @intCast(utf16_pos);
        icu.utrans_transUChars(pClonedTransliterator, cur_norm.ptr, &tlen, @intCast(cur_norm.len), 0, &tlimit, &ts);
        if (ts == c.U_BUFFER_OVERFLOW_ERROR) {
            const need: usize = @as(usize, @intCast(tlen)) + 64;
            if (use_stack) {
                heap_norm = try allocator.alloc(c.UChar, need);
                cur_norm = heap_norm.?;
            } else {
                heap_norm = try allocator.realloc(heap_norm.?, need);
                cur_norm = heap_norm.?;
            }
            @memcpy(cur_norm[0..utf16_pos], utf16_text_buffer[0..utf16_pos]);
            if (uses_russian_bgn) premapRussianYat(cur_norm[0..utf16_pos]);
            cur_norm[utf16_pos] = 0;
            tlen = @intCast(utf16_pos);
            tlimit = tlen;
            ts = c.U_ZERO_ERROR;
            icu.utrans_transUChars(pClonedTransliterator, cur_norm.ptr, &tlen, @intCast(cur_norm.len), 0, &tlimit, &ts);
        }
        if (c.U_FAILURE(ts)) return c.SQLITE_ERROR;

        const norm_len: usize = @intCast(tlen);
        normText = cur_norm[0..norm_len];

        // Bug #15: position map from normalized UTF-16 position -> original
        // UTF-16 position. Whitespace is an exact anchor under every rule
        // chain (see isSpaceLikeU16), so anchor at whitespace and use
        // round-half-up proportional scaling within each space-delimited
        // segment. The old whole-string proportional map compressed every
        // later position whenever any transliteration changed unit counts
        // (ﬁ->fi, щ->shch), misreporting offsets and silently dropping tokens
        // when mapped positions collided (nTokenByte <= 0).
        //
        // Bug #19: NFKD can also INSERT whitespace that does not exist in the
        // source — U+FDFA (ﷺ) decomposes into 19 units containing three real
        // spaces. Such "phantom" anchors must not steal original whitespace:
        // normalized spaces are therefore paired with original spaces from
        // the END (inserted spaces cluster inside expanded ligature content,
        // while structural sentence whitespace aligns terminally). Surplus
        // normalized spaces are treated as ordinary characters, and a deficit
        // (more original than normalized spaces) simply leaves the extra
        // original positions inside the trailing proportional segment.
        const pm_cap = norm_len + 1;
        const pm = if (pm_cap <= STACK_CAP * 3 + 1)
            stack_posmap[0..pm_cap]
        else blk2: {
            heap_posmap = try allocator.alloc(i32, pm_cap);
            break :blk2 heap_posmap.?;
        };
        var norm_space_total: usize = 0;
        for (normText) |ch| {
            if (isSpaceLikeU16(ch)) norm_space_total += 1;
        }
        var orig_space_total: usize = 0;
        for (utf16_text_buffer[0..utf16_pos]) |ch| {
            if (isSpaceLikeU16(ch)) orig_space_total += 1;
        }
        const phantom_spaces = if (norm_space_total > orig_space_total)
            norm_space_total - orig_space_total
        else
            0;

        var seen_norm_spaces: usize = 0;
        var orig_pos: usize = 0;
        var seg_orig_start: usize = 0;
        var seg_norm_start: usize = 0;
        var i: usize = 0;
        while (i < norm_len) : (i += 1) {
            if (!isSpaceLikeU16(normText[i])) continue;
            seen_norm_spaces += 1;
            if (seen_norm_spaces <= phantom_spaces) continue;
            while (orig_pos < utf16_pos and !isSpaceLikeU16(utf16_text_buffer[orig_pos])) {
                orig_pos += 1;
            }
            if (i > seg_norm_start) {
                fillSegment(pm, seg_norm_start, i, seg_orig_start, orig_pos);
            }
            pm[i] = @intCast(orig_pos);
            seg_orig_start = orig_pos + 1;
            seg_norm_start = i + 1;
            orig_pos += 1;
        }
        if (norm_len > seg_norm_start) {
            fillSegment(pm, seg_norm_start, norm_len, seg_orig_start, utf16_pos);
        }
        pm[norm_len] = @intCast(utf16_pos);
        position_map = pm;
    }

    // Set break iterator on the NORMALIZED text
    var brk_status: c.UErrorCode = c.U_ZERO_ERROR;
    icu.ubrk_setText(pBreakIterator, normText.ptr, @intCast(normText.len), &brk_status);
    if (c.U_FAILURE(brk_status)) return c.SQLITE_ERROR;

    var token_start = icu.ubrk_first(pBreakIterator);
    while (true) {
        const token_end = icu.ubrk_next(pBreakIterator);
        if (token_end == c.UBRK_DONE) break;

        if (token_start < 0 or token_end < 0 or @as(usize, @intCast(token_start)) >= normText.len or @as(usize, @intCast(token_end)) > normText.len) {
            token_start = token_end;
            continue;
        }

        const word_status = icu.ubrk_getRuleStatus(pBreakIterator);
        if (word_status >= c.UBRK_WORD_NONE and word_status < c.UBRK_WORD_NONE_LIMIT) {
            token_start = token_end;
            continue;
        }

        const t_start: usize = @intCast(token_start);
        const t_end: usize = @intCast(token_end);

        // Map normalized token positions back to original byte offsets
        const orig_start_u16 = position_map[t_start];
        const orig_end_u16 = position_map[t_end];
        const iStartByte = byte_offset_map[@intCast(orig_start_u16)];
        const iEndByte = byte_offset_map[@intCast(orig_end_u16)];
        const nTokenByte = iEndByte - iStartByte;
        if (nTokenByte <= 0) {
            token_start = token_end;
            continue;
        }

        const nSrc: usize = t_end - t_start;
        if (nSrc == 0) {
            token_start = token_end;
            continue;
        }

        // Convert the normalized token (UTF-16) to UTF-8
        var utf8_len: i32 = 0;
        const reqDest = nSrc * 4 + 64;
        if (destBuf.len < reqDest) {
            if (heap_dest) |hd| {
                heap_dest = try allocator.realloc(hd, reqDest);
                destBuf = heap_dest.?;
            } else {
                heap_dest = try allocator.alloc(u8, reqDest);
                destBuf = heap_dest.?;
            }
        }

        var conv_status: c.UErrorCode = c.U_ZERO_ERROR;
        _ = icu.u_strToUTF8WithSub(destBuf.ptr, @intCast(destBuf.len), &utf8_len, normText[t_start..].ptr, @intCast(nSrc), 0xFFFD, null, &conv_status);
        if (conv_status == c.U_BUFFER_OVERFLOW_ERROR or (c.U_FAILURE(conv_status) and utf8_len > @as(i32, @intCast(destBuf.len)))) {
            const newDestSize: usize = @intCast(utf8_len + 64);
            if (heap_dest) |hd| {
                heap_dest = try allocator.realloc(hd, newDestSize);
                destBuf = heap_dest.?;
            } else {
                heap_dest = try allocator.alloc(u8, newDestSize);
                destBuf = heap_dest.?;
            }
            utf8_len = 0;
            conv_status = c.U_ZERO_ERROR;
            _ = icu.u_strToUTF8WithSub(destBuf.ptr, @intCast(destBuf.len), &utf8_len, normText[t_start..].ptr, @intCast(nSrc), 0xFFFD, null, &conv_status);
        }

        if (!c.U_FAILURE(conv_status) and utf8_len > 0) {
            // Bug #18: strip transliteration modifier letters (U+02BF/U+02BB/
            // U+2019) from ar/he tokens so they are pure ASCII. This compacts
            // only the token text; the byte range still points at the original
            // word, and whitespace is unaffected, so the position map holds.
            if (uses_ar_he_latin) {
                utf8_len = stripTranslitMarks(destBuf[0..@intCast(utf8_len)]);
            }
            if (utf8_len > 0) {
                const rc = xToken(pCtx, 0, destBuf.ptr, utf8_len, iStartByte, iEndByte);
                if (rc != c.SQLITE_OK) {
                    return rc;
                }
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
    try std.testing.expect(std.mem.indexOf(u8, out, "russkiy") != null);
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

// Bug #11: tokenizeText clones the break iterator per call (via icu.ubrk_clone
// after the fix, removing the dead resolver). This exercises that clone path by
// tokenizing mixed CJK + Latin text that needs real word segmentation and
// asserting tokens are produced (including the Latin word as its own token).
test "tokenizeText break-iterator clone path (bug #11)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    var cap: Capture = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t);
        cap.tokens.deinit(gpa);
    }

    const rc = try tokenizeText(gpa, tok, "日本語のテスト and English", null, &cap, captureTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);
    try std.testing.expect(cap.tokens.items.len > 0);

    var found_english = false;
    for (cap.tokens.items) |t| {
        if (std.mem.eql(u8, t, "english")) found_english = true;
    }
    try std.testing.expect(found_english);
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
    if (!has_ubrk_clone) return error.SkipZigTest;

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

    var thread_errors: std.atomic.Value(usize) = .init(0);
    const ThreadContext = struct {
        tokenizer: *IcuTokenizer,
        text: []const u8,
        errors: *std.atomic.Value(usize),
        fn worker(self: @This()) void {
            const rc = tokenizeText(std.heap.c_allocator, self.tokenizer, self.text, null, null, dummyTokenCallback) catch c.SQLITE_ERROR;
            if (rc != c.SQLITE_OK) {
                _ = self.errors.fetchAdd(1, .monotonic);
            }
        }
    };

    var threads: [8]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        const text = if (i % 2 == 0) "日本語のテスト text" else "English text and 日本語";
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{
            .tokenizer = tok,
            .text = text,
            .errors = &thread_errors,
        }});
    }

    for (threads) |t| {
        t.join();
    }
    try std.testing.expectEqual(@as(usize, 0), thread_errors.load(.monotonic));
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

    var thread_errors: std.atomic.Value(usize) = .init(0);
    const ThreadContext = struct {
        tokenizer: *IcuTokenizer,
        errors: *std.atomic.Value(usize),
        fn worker(self: @This()) void {
            const rc = tokenizeText(
                std.heap.c_allocator,
                self.tokenizer,
                "русский текст пример",
                null,
                null,
                dummyTokenCallback,
            ) catch c.SQLITE_ERROR;
            if (rc != c.SQLITE_OK) {
                _ = self.errors.fetchAdd(1, .monotonic);
            }
        }
    };

    var threads: [8]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{ .tokenizer = tok, .errors = &thread_errors }});
    }
    for (threads) |t| t.join();
    try std.testing.expectEqual(@as(usize, 0), thread_errors.load(.monotonic));
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
        if (std.mem.eql(u8, t, "russkiy")) found_russian = true;
        if (std.mem.eql(u8, t, "francais")) found_french = true;
    }
    try std.testing.expect(cap.tokens.items.len >= 6);
    try std.testing.expect(found_russian);
    try std.testing.expect(found_french);
}

// Bug #14: Cyrillic-Latin collapses щ/ш/с -> s and ж/з -> z (борщ/борс, шар/сар,
// жар/зар become identical tokens). Russian-Latin/BGN keeps them distinct, and
// the й->y pre-map keeps мой/мои apart (мой->moy, мои->moi).
test "tokenizeText Russian BGN keeps letters distinct (bug #14)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "ru");
    defer tok.destroy(gpa);

    const text = "борщ борс шар сар жар зар мой мои русский";
    var cap: Capture = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t);
        cap.tokens.deinit(gpa);
    }
    const rc = try tokenizeText(gpa, tok, text, null, &cap, captureTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);

    var found = [_]bool{false} ** 9;
    for (cap.tokens.items) |t| {
        if (std.mem.eql(u8, t, "borshch")) found[0] = true;
        if (std.mem.eql(u8, t, "bors")) found[1] = true;
        if (std.mem.eql(u8, t, "shar")) found[2] = true;
        if (std.mem.eql(u8, t, "sar")) found[3] = true;
        if (std.mem.eql(u8, t, "zhar")) found[4] = true;
        if (std.mem.eql(u8, t, "zar")) found[5] = true;
        if (std.mem.eql(u8, t, "moy")) found[6] = true;
        if (std.mem.eql(u8, t, "moi")) found[7] = true;
        if (std.mem.eql(u8, t, "russkiy")) found[8] = true;
    }
    for (found) |f| try std.testing.expect(f);
}

// Bug #15: transliteration expansions (ﬁ->fi, щ->shch) must not skew the byte
// offsets of later tokens. Whitespace anchors each segment exactly; the old
// whole-string proportional map misreported offsets and dropped tokens here.
test "tokenizeText expansion keeps byte offsets (bug #15)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    var cap: CaptureWithRange = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t.text);
        cap.tokens.deinit(gpa);
    }

    // "a ﬁ b": ﬁ (U+FB01) is 3 UTF-8 bytes / 1 UTF-16 unit and expands to two
    // normalized units, but must still map back to bytes [2,5).
    _ = try tokenizeText(gpa, tok, "a ﬁ b", null, &cap, captureRangeCallback);
    for (cap.tokens.items) |t| {
        if (std.mem.eql(u8, t.text, "fi")) {
            try std.testing.expectEqual(@as(i32, 2), t.i_start);
            try std.testing.expectEqual(@as(i32, 5), t.i_end);
        }
        if (std.mem.eql(u8, t.text, "a")) {
            try std.testing.expectEqual(@as(i32, 0), t.i_start);
            try std.testing.expectEqual(@as(i32, 1), t.i_end);
        }
        if (std.mem.eql(u8, t.text, "b")) {
            try std.testing.expectEqual(@as(i32, 6), t.i_start);
            try std.testing.expectEqual(@as(i32, 7), t.i_end);
        }
    }

    // 1->5 unit expansion (щ -> shch) with Russian BGN rules: "борщ вкусный"
    // (4+1+7 UTF-16 units, 8+1+14 bytes) -> borshch [0,8), vkusnyy [9,23).
    for (cap.tokens.items) |t| gpa.free(t.text);
    cap.tokens.clearRetainingCapacity();
    _ = try tokenizeText(gpa, tok, "борщ вкусный", "ru", &cap, captureRangeCallback);
    for (cap.tokens.items) |t| {
        if (std.mem.eql(u8, t.text, "borshch")) {
            try std.testing.expectEqual(@as(i32, 0), t.i_start);
            try std.testing.expectEqual(@as(i32, 8), t.i_end);
        }
        if (std.mem.eql(u8, t.text, "vkusnyy")) {
            try std.testing.expectEqual(@as(i32, 9), t.i_start);
            try std.testing.expectEqual(@as(i32, 23), t.i_end);
        }
    }
}

// Bug #16: garbage locales (e.g. "xx_YY") were silently accepted — ubrk_open
// falls back to root rules for ANY non-empty locale (verified by probe on
// ICU 78 and 67.1.0), so the fallback warning cannot reject them. Validation
// now checks the locale's language against supported aliases and ICU's
// available-locale list at create time; a bad locale fails fast instead of
// silently tokenizing as English.
test "create rejects unresolvable locale (bug #16)" {
    const gpa = std.testing.allocator;

    try std.testing.expectError(error.IcuInvalidLocale, IcuTokenizer.create(gpa, "xx"));
    try std.testing.expectError(error.IcuInvalidLocale, IcuTokenizer.create(gpa, "xx_YY"));
    try std.testing.expectError(error.IcuInvalidLocale, IcuTokenizer.create(gpa, "xyz"));
}

// Bug #16 (positive side): the rules.zig aliases (jp/cn/kr) are not ICU
// language codes and "C"/"POSIX" are not in the available list, but they must
// still create fine; likewise real locales with variants/encodings.
test "create accepts supported aliases and real locales (bug #16)" {
    const gpa = std.testing.allocator;

    {
        const tok = try IcuTokenizer.create(gpa, "jp");
        defer tok.destroy(gpa);
    }
    {
        const tok = try IcuTokenizer.create(gpa, "cn");
        defer tok.destroy(gpa);
    }
    {
        const tok = try IcuTokenizer.create(gpa, "kr");
        defer tok.destroy(gpa);
    }
    {
        const tok = try IcuTokenizer.create(gpa, "en_US.UTF-8");
        defer tok.destroy(gpa);
    }
    {
        const tok = try IcuTokenizer.create(gpa, "C");
        defer tok.destroy(gpa);
    }
    {
        const tok = try IcuTokenizer.create(gpa, "POSIX");
        defer tok.destroy(gpa);
    }
}

// Bug #18: Arabic-Latin leaves the modifier letter U+02BF (ʿ) in tokens
// (probe: 'العربية' -> 'alʿrbyt'), so Arabic tokens were not pure ASCII and
// Latin-spelled queries could not match them. ʿ is now stripped from the
// token text (positions unchanged), so tokens are pure ASCII.
test "tokenizeText Arabic tokens are pure ASCII (bug #18)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "ar");
    defer tok.destroy(gpa);

    const text = "العربية عربية قرآن سؤال";
    var cap: Capture = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t);
        cap.tokens.deinit(gpa);
    }
    const rc = try tokenizeText(gpa, tok, text, null, &cap, captureTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);

    try std.testing.expect(cap.tokens.items.len >= 4);
    for (cap.tokens.items) |t| {
        for (t) |b| try std.testing.expect(b < 0x80);
    }
    var found = [_]bool{false} ** 4;
    for (cap.tokens.items) |t| {
        if (std.mem.eql(u8, t, "alrbyt")) found[0] = true;
        if (std.mem.eql(u8, t, "rbyt")) found[1] = true;
        if (std.mem.eql(u8, t, "qran")) found[2] = true;
        if (std.mem.eql(u8, t, "swal")) found[3] = true;
    }
    for (found) |f| try std.testing.expect(f);
}

// Bug #18: transliterateString must also return pure ASCII for ar/he rules
// (Hebrew-Latin may emit U+02BB/U+2019 on some ICU versions).
test "transliterateString ar/he output is pure ASCII (bug #18)" {
    const gpa = std.testing.allocator;

    const ar = try transliterateString(gpa, "العربية", rules.ICU_RULE_AR);
    defer gpa.free(ar);
    for (ar) |b| try std.testing.expect(b < 0x80);
    try std.testing.expect(std.mem.eql(u8, ar, "alrbyt"));

    const he = try transliterateString(gpa, "אמונה", rules.ICU_RULE_HE);
    defer gpa.free(he);
    for (he) |b| try std.testing.expect(b < 0x80);
}

// Bug #14 + #18 through the UNIVERSAL tokenizer (empty locale, ICU_RULE_DEFAULT
// chains). Both fixes are gated on rule strings (Russian-Latin/BGN,
// Arabic-Latin), so they must hold for the universal tokenizer exactly as for
// the locale-specific libraries: Russian letters stay distinct (borshch/shar/
// zhar/moy/moi) and Arabic tokens are pure ASCII.
test "universal tokenizer applies Russian BGN and Arabic mark strip (bug #14/#18)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    var cap: Capture = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t);
        cap.tokens.deinit(gpa);
    }
    const text = "борщ шар жар мой мои العربية عربية";
    const rc = try tokenizeText(gpa, tok, text, null, &cap, captureTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);

    try std.testing.expect(cap.tokens.items.len >= 7);
    var found = [_]bool{false} ** 7;
    for (cap.tokens.items) |t| {
        for (t) |b| try std.testing.expect(b < 0x80);
        if (std.mem.eql(u8, t, "borshch")) found[0] = true;
        if (std.mem.eql(u8, t, "shar")) found[1] = true;
        if (std.mem.eql(u8, t, "zhar")) found[2] = true;
        if (std.mem.eql(u8, t, "moy")) found[3] = true;
        if (std.mem.eql(u8, t, "moi")) found[4] = true;
        if (std.mem.eql(u8, t, "alrbyt")) found[5] = true;
        if (std.mem.eql(u8, t, "rbyt")) found[6] = true;
    }
    for (found) |f| try std.testing.expect(f);
}

// Bug #12: `u_strFromUTF8` was removed (dead; utf8ToUtf16Alloc uses the std
// UTF-16 converter). This confirms the live transliteration path still works end
// to end — rule string -> std UTF-16 conversion -> utrans -> UTF-8 — with no
// dependency on u_strFromUTF8.
test "transliterateString works without u_strFromUTF8 (bug #12)" {
    const gpa = std.testing.allocator;

    const out = try transliterateString(gpa, "Ελληνικά", rules.ICU_RULE_DEFAULT);
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
    // Greek must be Latinized to pure ASCII (no u_strFromUTF8 involved).
    for (out) |b| try std.testing.expect(b < 0x80);
    try std.testing.expect(std.mem.indexOf(u8, out, "ellenika") != null);
}

test "ja pre-transliteration: hiragana+ー produces single token" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "ja");
    defer tok.destroy(gpa);

    // Katakana input: should be one token
    var cap_kata: Capture = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap_kata.tokens.items) |t| gpa.free(t);
        cap_kata.tokens.deinit(gpa);
    }
    _ = try tokenizeText(gpa, tok, "スーパーマーケット", null, &cap_kata, captureTokenCallback);
    try std.testing.expectEqual(@as(usize, 1), cap_kata.tokens.items.len);

    // Hiragana+ー input: must also be one token (without pre-transliteration,
    // UBRK_WORD would fragment this into 8 pieces)
    var cap_hira: Capture = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap_hira.tokens.items) |t| gpa.free(t);
        cap_hira.tokens.deinit(gpa);
    }
    _ = try tokenizeText(gpa, tok, "すーぱーまーけっと", null, &cap_hira, captureTokenCallback);
    try std.testing.expectEqual(@as(usize, 1), cap_hira.tokens.items.len);

    // Both paths converge to the same normalized token
    try std.testing.expectEqualStrings(cap_kata.tokens.items[0], cap_hira.tokens.items[0]);
}

// Bug #19: NFKD expands U+FDFA (ﷺ) into 19 UTF-16 units that CONTAIN three
// spaces absent from the source. The old start-paired anchor map let those
// phantom spaces steal the input's real space: tokens were emitted with byte
// ranges of unrelated words (the franken-token 'lyh' claimed the bytes of 'z')
// and real words were silently dropped. With end-pairing, every emitted range
// must stay inside the source, the final word must survive, and no token may
// claim a range it cannot own.
test "tokenizeText ligature-inserted whitespace keeps ranges sane (bug #19)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    // bytes: x=0, ﷺ=1..4, y=4, space=5, z=6 (len 7)
    var cap: CaptureWithRange = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t.text);
        cap.tokens.deinit(gpa);
    }
    const rc = try tokenizeText(gpa, tok, "xﷺy z", null, &cap, captureRangeCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);
    try std.testing.expect(cap.tokens.items.len > 0);

    var found_z = false;
    for (cap.tokens.items) |t| {
        // Every range must be non-empty and within the source text.
        try std.testing.expect(t.i_start >= 0);
        try std.testing.expect(t.i_start < t.i_end);
        try std.testing.expect(t.i_end <= @as(i32, @intCast("x\u{FDFA}y z".len)));
        // The pre-fix franken signature: 'lyh' claiming the bytes of 'z'.
        try std.testing.expect(!(std.mem.eql(u8, t.text, "lyh") and t.i_start == 6));
        if (std.mem.eql(u8, t.text, "z")) found_z = true;
    }
    // The last source word must not be lost to phantom-space misalignment.
    try std.testing.expect(found_z);
}
