const std = @import("std");
const compat = @import("compat.zig");
const c = @import("c");
const icu = @import("c_icu");
const rules = @import("rules.zig");

// Bug #22: single definition lives in c_icu.zig next to the ubrk_clone
// resolver it gates.
const has_ubrk_clone = icu.has_ubrk_clone;

// Bug #26: the FTS5 C-callback chain cannot provide the `io` handle that
// `std.Io.Mutex` requires (and `std.Thread.Mutex` no longer exists in
// 0.16), so the override cache is guarded by this small spin-yield mutex
// built directly on atomics. Critical sections are short (a string compare
// plus clones on hits); only a differing-locale miss holds it across ICU
// opens, which is rare and still correct under contention.
const CacheMutex = struct {
    state: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),

    // Bug #39: test-and-test-and-set. Waiters spin on a plain relaxed LOAD
    // (the cache line stays shared across cores) and only attempt the atomic
    // read-modify-write once the lock looks free; a strong cmpxchg on every
    // iteration kept stealing the line exclusively from the holder.
    // cmpxchgWeak is enough because a spurious failure just loops again.
    // Infallible: if the OS refuses to yield (error.SystemCannotYield) we keep
    // spinning instead of failing the whole tokenizeText call.
    fn lock(m: *CacheMutex) void {
        var spins: usize = 0;
        while (true) {
            if (m.state.load(.monotonic) == 0 and
                m.state.cmpxchgWeak(0, 1, .acquire, .monotonic) == null) return;
            if (spins < 1000) {
                std.atomic.spinLoopHint();
                spins += 1;
            } else {
                std.Thread.yield() catch std.atomic.spinLoopHint();
            }
        }
    }

    fn unlock(m: *CacheMutex) void {
        m.state.store(0, .release);
    }
};

pub const IcuTokenizer = struct {
    pBreakIterator: ?*c.UBreakIterator,
    pTransliterator: ?*c.UTransliterator,
    locale_slice: []const u8,
    /// Allocator that owns the override-cache entries. Fixed at create:
    /// tokenizeText may be called with a different scratch allocator, which
    /// must never free cache memory.
    allocator: std.mem.Allocator,
    cache_mutex: CacheMutex = .{},
    cached_locale: ?[]u8 = null,
    cached_break: ?*c.UBreakIterator = null,
    cached_trans: ?*c.UTransliterator = null,

    pub fn create(allocator: std.mem.Allocator, locale: []const u8) !*IcuTokenizer {
        var status: c.UErrorCode = c.U_ZERO_ERROR;

        const tok = try allocator.create(IcuTokenizer);
        errdefer allocator.destroy(tok);
        tok.* = .{
            .pBreakIterator = null,
            .pTransliterator = null,
            .locale_slice = try allocator.dupe(u8, locale),
            .allocator = allocator,
        };
        errdefer allocator.free(tok.locale_slice);

        const rule_str = rules.getRulesForLocale(locale);

        // Convert rule string to UTF-16
        const rules_u16 = try utf8ToUtf16Alloc(allocator, rule_str);
        defer allocator.free(rules_u16);

        // Convert locale string to zero-terminated C string
        const locale_c = try compat.dupeZ(allocator, locale);
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
        // No lock: destroy has exclusive access by contract (FTS5 calls
        // xDelete after the last xTokenize). Cache entries were allocated
        // with the stored create-time allocator.
        if (self.cached_break) |b| icu.ubrk_close(b);
        if (self.cached_trans) |t| icu.utrans_close(t);
        if (self.cached_locale) |cl| self.allocator.free(cl);
        allocator.free(self.locale_slice);
        allocator.destroy(self);
    }
};

pub fn utf8ToUtf16Alloc(allocator: std.mem.Allocator, text: []const u8) ![:0]c.UChar {
    // Use the std UTF-8 -> UTF-16 converter (bug #7). utf8ToUtf16LeAllocZ
    // returns [:0]u16, identical to [:0]c.UChar, so every caller is unchanged.
    return std.unicode.utf8ToUtf16LeAllocZ(allocator, text);
}

// Bug #27: every ICU length parameter below is an i32, and several
// intermediate sizes derive from the input length (UTF-16 units <= bytes,
// normalized <= 3x + 64, UTF-8 token buffer <= 4x + 64). Inputs larger than
// this cap could overflow an unchecked @intCast — silent wrap plus disabled
// bounds checks in ReleaseFast. 128 MiB keeps every derived size under
// ~1.6 GiB, comfortably inside i32 range; larger inputs fail loudly.
pub const max_text_len: usize = 128 * 1024 * 1024;

// Bug #29: bound on transliteration grow-and-retry loops. ICU reports the
// exact size needed on overflow, so one retry always suffices in practice;
// the loop is defense against a misbehaving ICU build, and persistent
// overflow fails loudly at the existing U_FAILURE checks below instead of
// looping forever or silently dropping data.
const max_translit_retries: u32 = 8;

// Bug #37: grow an optional heap fallback buffer. Whether to `alloc` or
// `realloc` must be decided from the buffer's CURRENT state, never from a flag
// computed before a retry loop: a flag like "started on the stack" stays true
// on later iterations, so a second overflow would `alloc` over (and leak) the
// heap buffer the first overflow had already installed. On failure `slot` is
// left untouched, so the caller's `defer free` still owns the old buffer
// exactly once (no double free, bug #8).
fn growHeapBuf(comptime T: type, allocator: std.mem.Allocator, slot: *?[]T, need: usize) !void {
    if (slot.*) |old| {
        slot.* = try allocator.realloc(old, need);
    } else {
        slot.* = try allocator.alloc(T, need);
    }
}

// Bug #38: ICU reports lengths as i32 and takes capacities as i32. A grown
// buffer size is `len + headroom`; doing that addition in i32 (`utf8_len + 64`)
// overflows near maxInt(i32) — a panic in Debug, a silent wrap in ReleaseFast
// — and a later `@intCast(need)` back to i32 is unchecked. Widen to usize
// first, then verify the result still fits an i32 capacity before any caller
// hands it to ICU. A negative `len` (never produced by a healthy ICU) is
// rejected rather than cast.
fn grownLen(len: i32, headroom: usize) error{TextTooLarge}!usize {
    if (len < 0) return error.TextTooLarge;
    const need = @as(usize, @intCast(len)) + headroom;
    if (need > std.math.maxInt(i32)) return error.TextTooLarge;
    return need;
}

pub fn transliterateString(allocator: std.mem.Allocator, input: []const u8, rule_str: []const u8) ![]u8 {
    if (input.len > max_text_len) return error.TextTooLarge;
    // Bug #34/#42: sniff rule features via rules.sniffRuleFeatures.
    const rule_feats = rules.sniffRuleFeatures(rule_str);
    const wants_russian_bgn = rule_feats.uses_russian_bgn;
    const wants_ar_he_latin = rule_feats.uses_ar_he_latin;
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
    if (wants_russian_bgn) {
        premapRussianYat(output_u16[0..input_u16.len]);
    }

    var limit: i32 = @intCast(input_u16.len);
    var out_len: i32 = @intCast(input_u16.len);
    status = c.U_ZERO_ERROR;
    icu.utrans_transUChars(transliterator, output_u16.ptr, &out_len, @intCast(capacity), 0, &limit, &status);
    var expand_retries: u32 = 0;
    while (status == c.U_BUFFER_OVERFLOW_ERROR and expand_retries < max_translit_retries) : (expand_retries += 1) {
        // Transliteration expanded beyond the buffer (bug #3): grow to the
        // required length and retry, instead of returning an error.
        //
        // Bug #8 fix: allocate the replacement buffer into a temporary first,
        // then swap. The previous code freed `output_u16` and reassigned it
        // before the `try`; on OutOfMemory the `defer allocator.free(output_u16)`
        // would run on the already-freed pointer (double free, CWE-415). By
        // allocating into `new_u16` first, a failed realloc leaves `output_u16`
        // pointing at the still-valid original buffer, which `defer` frees once.
        // Bug #38: widened, i32-range-checked size; the @intCast(need) below
        // is therefore safe.
        const need = try grownLen(out_len, 64);
        const new_u16 = try allocator.alloc(c.UChar, need);
        allocator.free(output_u16);
        output_u16 = new_u16;
        @memcpy(output_u16[0..input_u16.len], input_u16);
        if (wants_russian_bgn) {
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
    // Bug #38: `utf8_len + 1` was added in i32; widen first and range-check.
    const utf8_cap = try grownLen(utf8_len, 1);
    const buf_with_nul = try allocator.alloc(u8, utf8_cap);

    _ = icu.u_strToUTF8(buf_with_nul.ptr, @intCast(utf8_cap), null, output_u16.ptr, limit, &status);
    if (c.U_FAILURE(status)) {
        allocator.free(buf_with_nul);
        return error.Utf8ConvertFailed;
    }

    // Bug #18: strip Arabic-Latin/Hebrew-Latin modifier letters (U+02BF/
    // U+02BB/U+2019) so the returned string is pure ASCII.
    const final_len: i32 = if (wants_ar_he_latin)
        stripTranslitMarks(buf_with_nul[0..@as(usize, @intCast(utf8_len))])
    else
        @intCast(utf8_len);

    // Bug #34: return the (shrunk) conversion buffer directly instead of
    // copying it once more with dupe. Shrinking realloc cannot
    // meaningfully fail, but the fallback keeps ownership airtight.
    const final_len_usize: usize = @intCast(final_len);
    if (final_len_usize == 0) {
        allocator.free(buf_with_nul);
        return allocator.dupe(u8, "");
    }
    const shrunk = allocator.realloc(buf_with_nul, final_len_usize) catch {
        const out = allocator.dupe(u8, buf_with_nul[0..final_len_usize]) catch |err| {
            allocator.free(buf_with_nul);
            return err;
        };
        allocator.free(buf_with_nul);
        return out;
    };
    return shrunk;
}

// Bug #40: single-pass, tolerant UTF-8 -> UTF-16 conversion that also fills the
// byte-offset map (utf16 index -> utf8 start byte; both units of a surrogate
// pair map to the pair's first byte). For valid UTF-8 the output is identical
// to std.unicode.utf8ToUtf16Le. This replaces the former "utf8ToUtf16Le, then
// re-decode the whole text again in buildByteOffsetMap" hot path (every valid
// document was decoded twice) and the duplicated decoder loop between those
// two functions. Pure-ASCII runs take a tight 1-byte -> 1-unit loop with no
// per-character decoding.
//
// Malformed input is tolerated exactly as before: an invalid or truncated
// multi-byte sequence becomes one U+FFFD, while a lone byte that cannot start
// a sequence (0x80..0xBF, 0xF8..0xFF) keeps its byte value as a codepoint
// (std's utf8Decode returns a 1-byte slice unchecked).
// Returns the number of UTF-16 units written.
fn convertUtf8ToUtf16Tolerant(
    utf16_buf: []c.UChar,
    map: []i32,
    text: []const u8,
) usize {
    // Never write past either output, whatever sizes the caller passed.
    const cap = @min(utf16_buf.len, map.len);
    var utf16_pos: usize = 0;
    var utf8_pos: usize = 0;
    while (utf8_pos < text.len and utf16_pos < cap) {
        if (text[utf8_pos] < 0x80) {
            // ASCII fast path: consume the whole run that fits.
            const run_max = @min(text.len - utf8_pos, cap - utf16_pos);
            var n: usize = 0;
            while (n < run_max and text[utf8_pos + n] < 0x80) : (n += 1) {
                utf16_buf[utf16_pos + n] = text[utf8_pos + n];
                map[utf16_pos + n] = @intCast(utf8_pos + n);
            }
            utf16_pos += n;
            utf8_pos += n;
            continue;
        }

        const orig_utf8 = utf8_pos;
        const cp_len = std.unicode.utf8ByteSequenceLength(text[utf8_pos]) catch 1;
        const end = @min(utf8_pos + cp_len, text.len);
        // A sequence cut off by the end of the text is shorter than its lead
        // byte promises; std's utf8Decode2/3/4 assert on that (panic in Debug
        // and ReleaseSafe), so substitute U+FFFD instead of decoding it.
        const cp: u21 = if (end - utf8_pos == cp_len)
            std.unicode.utf8Decode(text[utf8_pos..end]) catch 0xFFFD
        else
            0xFFFD;
        utf8_pos = end;

        if (cp <= 0xFFFF) {
            utf16_buf[utf16_pos] = @intCast(cp);
            map[utf16_pos] = @intCast(orig_utf8);
            utf16_pos += 1;
        } else {
            if (utf16_pos + 2 > cap) break;
            utf16_buf[utf16_pos] = @intCast(0xD800 + ((cp - 0x10000) >> 10));
            utf16_buf[utf16_pos + 1] = @intCast(0xDC00 + ((cp - 0x10000) & 0x3FF));
            map[utf16_pos] = @intCast(orig_utf8);
            map[utf16_pos + 1] = @intCast(orig_utf8);
            utf16_pos += 2;
        }
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
    // Bug #31: a degenerate — or, defensively, inverted — original span pins
    // to its boundary instead of dividing by zero or underflowing `oe - os`
    // (Debug panic / ReleaseFast wrap). Inverted spans cannot occur today
    // (see the phantom-space accounting), but a future rule change must not
    // turn them into memory-unsafety or uninitialized map reads.
    if (os >= oe) {
        for (ns..ne) |k| pm[k] = @intCast(@min(os, oe));
        return;
    }
    const seg_orig_len = oe - os;
    for (ns..ne) |k| {
        const rel = (k - ns) * seg_orig_len;
        pm[k] = @intCast(os + (rel + seg_norm_len / 2) / seg_norm_len);
    }
}

// Bug #15/#19 position map, extracted from tokenizeText so it can be tested in
// isolation. Fills `pm[0..norm.len + 1]` (normalized UTF-16 position ->
// original UTF-16 position) by anchoring on whitespace and scaling
// proportionally inside each space-delimited segment (the rationale for the
// anchoring and the end-pairing of phantom spaces is in the bug #15 / #19
// notes above the call in tokenizeText). `pm.len` must be at least
// `norm.len + 1`.
//
// Bug #41: the original text's spaces only matter for counting phantom
// (NFKD-inserted) normalized spaces. With zero normalized spaces there are no
// anchors and no phantoms, so the whole original-text scan is skipped — the
// common case for single words and CJK queries.
fn fillPositionMap(pm: []i32, norm: []const c.UChar, orig: []const c.UChar) void {
    const norm_len = norm.len;
    const orig_len = orig.len;

    var norm_space_total: usize = 0;
    for (norm) |ch| {
        if (isSpaceLikeU16(ch)) norm_space_total += 1;
    }
    var phantom_spaces: usize = 0;
    if (norm_space_total > 0) {
        var orig_space_total: usize = 0;
        for (orig) |ch| {
            if (isSpaceLikeU16(ch)) orig_space_total += 1;
        }
        if (norm_space_total > orig_space_total) phantom_spaces = norm_space_total - orig_space_total;
    }

    var seen_norm_spaces: usize = 0;
    var orig_pos: usize = 0;
    var seg_orig_start: usize = 0;
    var seg_norm_start: usize = 0;
    var i: usize = 0;
    while (i < norm_len) : (i += 1) {
        if (!isSpaceLikeU16(norm[i])) continue;
        seen_norm_spaces += 1;
        if (seen_norm_spaces <= phantom_spaces) continue;
        while (orig_pos < orig_len and !isSpaceLikeU16(orig[orig_pos])) {
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
        fillSegment(pm, seg_norm_start, norm_len, seg_orig_start, orig_len);
    }
    pm[norm_len] = @intCast(orig_len);
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

    // Bug #35: sized for the BCP47 maximum (primary subtags run 2-8
    // characters) with wide headroom, so extra-long subtags get a real
    // lookup instead of a blanket reject. Anything still over-long is
    // rejected cleanly by the checks below, never truncated.
    var lang_buf: [64]u8 = undefined;
    var st: c.UErrorCode = c.U_ZERO_ERROR;
    const n = icu.uloc_getLanguage(locale_c, &lang_buf, lang_buf.len, &st);
    if (c.U_FAILURE(st) or n < 0 or @as(usize, @intCast(n)) > lang_buf.len) return false;
    const lang = lang_buf[0..@intCast(n)];

    // Bug #41/#42: check the 13 supported aliases via rules.isSupportedLanguageAlias,
    // plus "en" as a fast-path to skip the uloc_getAvailable scan below.
    if (rules.isSupportedLanguageAlias(lang) or std.mem.eql(u8, lang, "en")) return true;

    const count = icu.uloc_countAvailable();
    var i: i32 = 0;
    while (i < count) : (i += 1) {
        if (localeEntryHasLanguage(std.mem.span(icu.uloc_getAvailable(i)), lang)) return true;
    }
    return false;
}

// Bug #41: does an ICU locale identifier (as listed by uloc_getAvailable, e.g.
// "en", "en_US", "zh_Hans_CN", "kok_IN") belong to language `lang`? Compares
// the entry's language subtag — everything before the first '_' or '-' — so a
// language ICU lists ONLY under regional identifiers (no bare "kok" entry) is
// still recognized, while a mere string prefix is not ("kok_IN" is not "ko").
fn localeEntryHasLanguage(entry: []const u8, lang: []const u8) bool {
    const end = std.mem.findAny(u8, entry, "_-") orelse entry.len;
    return std.mem.eql(u8, entry[0..end], lang);
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
    if (text.len > max_text_len) return c.SQLITE_TOOBIG;

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

    // Convert UTF-8 -> UTF-16 and build the byte-offset map in ONE pass
    // (bug #40: valid text used to be decoded twice).
    const utf16_pos = convertUtf8ToUtf16Tolerant(utf16_text_buffer, byte_offset_map, text);
    if (utf16_pos < byte_offset_map.len) {
        byte_offset_map[utf16_pos] = @intCast(text.len);
    }

    // Effective locale mirrors the override logic below (non-empty override
    // wins, otherwise the tokenizer's own locale).
    const effective_locale: []const u8 = if (override_locale) |l|
        (if (l.len > 0) l else tokenizer.locale_slice)
    else
        tokenizer.locale_slice;
    // Bug #34: one locale lookup; the rule feature flags come precomputed
    // from getLocaleInfo instead of rescanning the rule text per flag.
    const locale_info = rules.getLocaleInfo(effective_locale);
    const uses_russian_bgn = locale_info.uses_russian_bgn;
    const uses_ar_he_latin = locale_info.uses_ar_he_latin;

    var baseBreakIterator = tokenizer.pBreakIterator.?;
    var pTransliterator = tokenizer.pTransliterator.?;

    // Bug #26: single-entry per-locale cache for query-time overrides. The
    // fast path (empty override, or one equal to the tokenizer's own locale)
    // uses the base handles with no locking. A differing override takes the
    // cache lock: hits borrow the cached handles, misses validate + open
    // fresh (existing code) and install. Borrowing and the per-call clones
    // below all happen under the lock so a concurrent evict cannot
    // close handles out from under a clone; the explicit unlock runs once
    // both clones are owned per-call. The errdefer covers Zig-error paths
    // (e.g. OOM inside the no-clone fallback); normal-error returns unlock
    // explicitly since errdefer does not run for those.
    var cache_locked = false;
    errdefer if (cache_locked) tokenizer.cache_mutex.unlock();

    if (override_locale) |loc| {
        if (loc.len > 0 and !std.mem.eql(u8, loc, tokenizer.locale_slice)) {
            tokenizer.cache_mutex.lock();
            cache_locked = true;

            const hit = if (tokenizer.cached_locale) |cl| std.mem.eql(u8, cl, loc) else false;
            if (hit) {
                baseBreakIterator = tokenizer.cached_break.?;
                pTransliterator = tokenizer.cached_trans.?;
            } else {
                var status: c.UErrorCode = c.U_ZERO_ERROR;
                const loc_c = try compat.dupeZ(allocator, loc);
                defer allocator.free(loc_c);

                // Bug #20: per-call overrides reach ubrk_open/utrans_openU at
                // query time and must pass the same isValidLocaleLanguage gate
                // as IcuTokenizer.create (bug #16); otherwise a typo'd row/query
                // locale silently tokenizes with the wrong rules while the same
                // string fails loudly at CREATE TABLE time.
                if (!isValidLocaleLanguage(loc_c.ptr)) {
                    tokenizer.cache_mutex.unlock();
                    cache_locked = false;
                    return c.SQLITE_ERROR;
                }

                const dyn_rules = rules.getRulesForLocale(loc);
                const dyn_rules_u16 = try utf8ToUtf16Alloc(allocator, dyn_rules);
                defer allocator.free(dyn_rules_u16);

                const fresh_break = icu.ubrk_open(c.UBRK_WORD, loc_c.ptr, null, 0, &status);
                if (c.U_FAILURE(status) or fresh_break == null) {
                    tokenizer.cache_mutex.unlock();
                    cache_locked = false;
                    return c.SQLITE_ERROR;
                }
                status = c.U_ZERO_ERROR;
                const fresh_trans = icu.utrans_openU(dyn_rules_u16.ptr, -1, c.UTRANS_FORWARD, null, 0, null, &status);
                if (c.U_FAILURE(status) or fresh_trans == null) {
                    icu.ubrk_close(fresh_break.?);
                    tokenizer.cache_mutex.unlock();
                    cache_locked = false;
                    return c.SQLITE_ERROR;
                }

                // Install: dupe the locale first so OOM leaves the previous
                // entry intact instead of evicting-then-failing.
                const owned = tokenizer.allocator.dupe(u8, loc) catch {
                    icu.ubrk_close(fresh_break.?);
                    icu.utrans_close(fresh_trans.?);
                    tokenizer.cache_mutex.unlock();
                    cache_locked = false;
                    return c.SQLITE_NOMEM;
                };
                if (tokenizer.cached_break) |b| icu.ubrk_close(b);
                if (tokenizer.cached_trans) |t| icu.utrans_close(t);
                if (tokenizer.cached_locale) |cl| tokenizer.allocator.free(cl);
                tokenizer.cached_locale = owned;
                tokenizer.cached_break = fresh_break;
                tokenizer.cached_trans = fresh_trans;
                baseBreakIterator = fresh_break.?;
                pTransliterator = fresh_trans.?;
            }
        }
    }

    // Clone break iterator for thread safety
    var clone_status: c.UErrorCode = c.U_ZERO_ERROR;
    const pBreakIterator = if (has_ubrk_clone)
        icu.ubrk_clone.?(baseBreakIterator, &clone_status)
    else blk: {
        // Bug #17: use the effective (per-call override, when present) locale
        // instead of the tokenizer's own, matching ubrk_clone behavior on
        // newer ICU.
        const locale_z = try compat.dupeZ(allocator, effective_locale);
        defer allocator.free(locale_z);
        break :blk icu.ubrk_open(c.UBRK_WORD, locale_z.ptr, null, 0, &clone_status);
    };
    if (c.U_FAILURE(clone_status) or pBreakIterator == null) {
        if (cache_locked) {
            tokenizer.cache_mutex.unlock();
            cache_locked = false;
        }
        return c.SQLITE_ERROR;
    }
    defer icu.ubrk_close(pBreakIterator);

    // Clone transliterator for thread safety
    var trans_clone_status: c.UErrorCode = c.U_ZERO_ERROR;
    const pClonedTransliterator = icu.utrans_clone(pTransliterator, &trans_clone_status);
    if (c.U_FAILURE(trans_clone_status) or pClonedTransliterator == null) {
        if (cache_locked) {
            tokenizer.cache_mutex.unlock();
            cache_locked = false;
        }
        return c.SQLITE_ERROR;
    }
    defer icu.utrans_close(pClonedTransliterator);

    // Both clones are now owned per-call; the borrowed cache handles are no
    // longer needed, so release the lock before the (potentially long) token
    // loop. xToken callbacks run unlocked, so re-entrant use cannot deadlock.
    if (cache_locked) {
        tokenizer.cache_mutex.unlock();
        cache_locked = false;
    }

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
        var norm_retries: u32 = 0;
        while (ts == c.U_BUFFER_OVERFLOW_ERROR and norm_retries < max_translit_retries) : (norm_retries += 1) {
            // Bug #38: widened, i32-range-checked size (the @intCast(cur_norm.len)
            // below stays in range); too-large input fails loudly.
            const need = grownLen(tlen, 64) catch return c.SQLITE_TOOBIG;
            // Bug #37: branch on heap_norm's actual state (via growHeapBuf),
            // not on the fixed `use_stack` flag, so a second overflow
            // reallocs instead of leaking the first heap buffer.
            try growHeapBuf(c.UChar, allocator, &heap_norm, need);
            cur_norm = heap_norm.?;
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
        fillPositionMap(pm, normText, utf16_text_buffer[0..utf16_pos]);
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
        // Bug #38: every ICU capacity below is passed as an i32, so the
        // heuristic size is clamped to that range (a rare, extreme token
        // overflows into the checked retry path instead of an unchecked cast).
        const reqDest = @min(nSrc * 4 + 64, std.math.maxInt(i32));
        if (destBuf.len < reqDest) {
            // Bug #42: reuse growHeapBuf helper
            try growHeapBuf(u8, allocator, &heap_dest, reqDest);
            destBuf = heap_dest.?;
        }

        var conv_status: c.UErrorCode = c.U_ZERO_ERROR;
        _ = icu.u_strToUTF8WithSub(destBuf.ptr, @intCast(destBuf.len), &utf8_len, normText[t_start..].ptr, @intCast(nSrc), 0xFFFD, null, &conv_status);
        var dest_retries: u32 = 0;
        while ((conv_status == c.U_BUFFER_OVERFLOW_ERROR or (c.U_FAILURE(conv_status) and utf8_len > @as(i32, @intCast(destBuf.len)))) and dest_retries < max_translit_retries) : (dest_retries += 1) {
            // Bug #38: widen before adding headroom; too-large fails loudly.
            const newDestSize = grownLen(utf8_len, 64) catch return c.SQLITE_TOOBIG;
            // Bug #42: reuse growHeapBuf helper
            try growHeapBuf(u8, allocator, &heap_dest, newDestSize);
            destBuf = heap_dest.?;
            utf8_len = 0;
            conv_status = c.U_ZERO_ERROR;
            _ = icu.u_strToUTF8WithSub(destBuf.ptr, @intCast(destBuf.len), &utf8_len, normText[t_start..].ptr, @intCast(nSrc), 0xFFFD, null, &conv_status);
        }

        // Bug #29: persistent encoding failure fails the document loudly
        // instead of silently dropping the token.
        if (c.U_FAILURE(conv_status)) return c.SQLITE_ERROR;

        if (utf8_len > 0) {
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

// Bug #27: oversized inputs must fail loudly at the boundary instead of
// overflowing an unchecked @intCast downstream. The guards above return
// before any allocation, so this test needs only the length, not the work.
test "oversized input is rejected, not cast-truncated (bug #27)" {
    const gpa = std.testing.allocator;

    const big = try gpa.alloc(u8, max_text_len + 1);
    defer gpa.free(big);
    @memset(big, 'a');

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    const rc = try tokenizeText(gpa, tok, big, null, null, dummyTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_TOOBIG), rc);
    try std.testing.expectError(error.TextTooLarge, transliterateString(gpa, big, rules.ICU_RULE_DEFAULT));
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

    var found = std.mem.zeroes([9]bool);
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

// Bug #31: an inverted original span must pin to its boundary, not
// underflow `oe - os` (Debug panic / ReleaseFast wrap). Same-file tests can
// reach the private helper directly.
test "fillSegment pins degenerate and inverted spans (bug #31)" {
    var deg: [3]i32 = undefined;
    fillSegment(&deg, 0, 3, 5, 5);
    for (deg) |v| try std.testing.expectEqual(@as(i32, 5), v);

    var inv: [4]i32 = undefined;
    fillSegment(&inv, 0, 4, 9, 3);
    for (inv) |v| try std.testing.expectEqual(@as(i32, 3), v);

    var empty: [2]i32 = .{ 7, 7 };
    fillSegment(&empty, 1, 1, 9, 3);
    try std.testing.expectEqual([2]i32{ 7, 7 }, empty);
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

// Bug #35: an over-long language subtag is cleanly rejected (never
// truncated, no panic); over-long but well-formed input reaches the real
// lookup instead of tripping the scratch buffer size.
test "create handles over-long language subtag gracefully (bug #35)" {
    const gpa = std.testing.allocator;

    try std.testing.expectError(error.IcuInvalidLocale, IcuTokenizer.create(gpa, "abcdefghijklmnopqrstuvwxy"));
    try std.testing.expectError(error.IcuInvalidLocale, IcuTokenizer.create(gpa, "abcdefghijklmnopqrstuvwxy_ZZ"));
}

// Bug #20: per-call (query-time) locale overrides reach ubrk_open /
// utrans_openU directly and must pass the same isValidLocaleLanguage gate as
// IcuTokenizer.create; a typo'd override must return SQLITE_ERROR instead of
// silently tokenizing with the wrong rules.
test "tokenizeText rejects invalid query-time override locale (bug #20)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    const rc_bad = try tokenizeText(gpa, tok, "hello world", "xx_NOPE", null, dummyTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_ERROR), rc_bad);

    // Valid overrides and the empty-string (use tokenizer locale) cases keep
    // working.
    const rc_good = try tokenizeText(gpa, tok, "hello world", "ja", null, dummyTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc_good);
    const rc_empty = try tokenizeText(gpa, tok, "hello world", "", null, dummyTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc_empty);
}

fn expectRangesEqual(a: []const TokenRange, b: []const TokenRange) !void {
    try std.testing.expectEqual(a.len, b.len);
    for (a, b) |x, y| {
        try std.testing.expectEqualStrings(x.text, y.text);
        try std.testing.expectEqual(x.i_start, y.i_start);
        try std.testing.expectEqual(x.i_end, y.i_end);
    }
}

fn expectOverrideMatches(
    gpa: std.mem.Allocator,
    tok: *IcuTokenizer,
    text: []const u8,
    override: ?[]const u8,
    expected: []const TokenRange,
) !void {
    var cap: CaptureWithRange = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t.text);
        cap.tokens.deinit(gpa);
    }
    const rc = try tokenizeText(gpa, tok, text, override, &cap, captureRangeCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);
    try expectRangesEqual(expected, cap.tokens.items);
}

// Bug #26: the single-entry override cache must return byte-identical
// results on miss, hit, eviction, and re-install, and an override equal to
// the tokenizer's own locale must behave exactly like no override.
test "override cache is correct across locales (bug #26)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    const text = "русский текст and english";

    var first: CaptureWithRange = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (first.tokens.items) |t| gpa.free(t.text);
        first.tokens.deinit(gpa);
    }
    const rc = try tokenizeText(gpa, tok, text, "ru", &first, captureRangeCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);
    try std.testing.expect(first.tokens.items.len > 0);

    // Cache hit: identical tokens and byte ranges.
    try expectOverrideMatches(gpa, tok, text, "ru", first.tokens.items);
    // Evict with another locale (must succeed and produce tokens), then
    // re-install the first locale: identical to the original miss.
    var evicted: CaptureWithRange = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (evicted.tokens.items) |t| gpa.free(t.text);
        evicted.tokens.deinit(gpa);
    }
    const rc_evict = try tokenizeText(gpa, tok, text, "ja", &evicted, captureRangeCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc_evict);
    try std.testing.expect(evicted.tokens.items.len > 0);
    try expectOverrideMatches(gpa, tok, text, "ru", first.tokens.items);

    // Fast path: override equal to the tokenizer's own locale == no override.
    const tok_ru = try IcuTokenizer.create(gpa, "ru");
    defer tok_ru.destroy(gpa);
    var baseline: CaptureWithRange = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (baseline.tokens.items) |t| gpa.free(t.text);
        baseline.tokens.deinit(gpa);
    }
    const rc2 = try tokenizeText(gpa, tok_ru, text, null, &baseline, captureRangeCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc2);
    try expectOverrideMatches(gpa, tok_ru, text, "ru", baseline.tokens.items);
}

// Bug #26: mixed overrides from multiple threads share one cache entry;
// the lock must keep borrowed handles alive across borrow+clone.
test "concurrent tokenizeText with mixed overrides (bug #26)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    var thread_errors: std.atomic.Value(usize) = .init(0);
    const ThreadContext = struct {
        tokenizer: *IcuTokenizer,
        errors: *std.atomic.Value(usize),
        idx: usize,
        fn worker(self: @This()) void {
            const locales = [_]?[]const u8{ "ru", "ja", null, "ru" };
            const loc = locales[self.idx % locales.len];
            const rc = tokenizeText(std.heap.c_allocator, self.tokenizer, "русский текст 日本語テスト", loc, null, dummyTokenCallback) catch c.SQLITE_ERROR;
            if (rc != c.SQLITE_OK) {
                _ = self.errors.fetchAdd(1, .monotonic);
            }
        }
    };

    var threads: [8]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{
            .tokenizer = tok,
            .errors = &thread_errors,
            .idx = i,
        }});
    }
    for (threads) |t| t.join();
    try std.testing.expectEqual(@as(usize, 0), thread_errors.load(.monotonic));
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
    var found = std.mem.zeroes([4]bool);
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
    var found = std.mem.zeroes([7]bool);
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

// Bug #28: the reordered universal chain must still open in ICU and
// tokenize CJK + Latin end to end, with Lower applied last (English ->
// english) and every byte range inside the source text.
test "universal CJK tokenization after chain reorder (bug #28)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    const text = "日本語テスト and English";
    var cap: CaptureWithRange = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t.text);
        cap.tokens.deinit(gpa);
    }
    const rc = try tokenizeText(gpa, tok, text, null, &cap, captureRangeCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);
    try std.testing.expect(cap.tokens.items.len > 0);

    var found_english = false;
    for (cap.tokens.items) |t| {
        try std.testing.expect(t.i_start >= 0);
        try std.testing.expect(t.i_start < t.i_end);
        try std.testing.expect(t.i_end <= @as(i32, @intCast(text.len)));
        if (std.mem.eql(u8, t.text, "english")) {
            found_english = true;
            try std.testing.expectEqual(@as(i32, 23), t.i_start);
            try std.testing.expectEqual(@as(i32, 30), t.i_end);
        }
    }
    try std.testing.expect(found_english);
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

// Bug #37: the pre-transliteration retry loop chose `alloc` vs `realloc` from
// a flag fixed before the loop ("started on the stack"), so a SECOND overflow
// `alloc`ed over the buffer the first one had installed and leaked it. The
// real ICU reports the exact size on the first overflow, so this path cannot
// be provoked end to end; the decision now lives in `growHeapBuf`, which is
// tested directly. The testing allocator fails the test on any leaked
// intermediate buffer.
test "growHeapBuf grows repeatedly without leaking (bug #37)" {
    const gpa = std.testing.allocator;

    var slot: ?[]c.UChar = null;
    defer if (slot) |buf| gpa.free(buf);

    // First growth starts from "no heap buffer yet" (stack-start case).
    try growHeapBuf(c.UChar, gpa, &slot, 100);
    try std.testing.expectEqual(@as(usize, 100), slot.?.len);
    @memset(slot.?, 0x41);

    // Second and third growth must realloc the existing buffer, not alloc a
    // new one over it.
    try growHeapBuf(c.UChar, gpa, &slot, 400);
    try std.testing.expectEqual(@as(usize, 400), slot.?.len);
    try std.testing.expectEqual(@as(c.UChar, 0x41), slot.?[99]); // realloc preserves contents

    try growHeapBuf(c.UChar, gpa, &slot, 1600);
    try std.testing.expectEqual(@as(usize, 1600), slot.?.len);
}

test "growHeapBuf leaves the slot intact on OutOfMemory (bug #37)" {
    var slot: ?[]u8 = null;
    // fail_index = 1: the first allocation succeeds, the next one fails.
    // resize_fail_index = 0: in-place resize/remap is refused, so the realloc
    // must fall back to a (failing) allocation.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 1,
        .resize_fail_index = 0,
    });
    const fa = failing.allocator();
    defer if (slot) |buf| std.testing.allocator.free(buf);

    try growHeapBuf(u8, fa, &slot, 64);
    const before = slot.?;

    try std.testing.expectError(error.OutOfMemory, growHeapBuf(u8, fa, &slot, 4096));
    // The old buffer is still the slot's, so the single `defer free` above
    // releases it exactly once (no leak, no double free).
    try std.testing.expectEqual(before.ptr, slot.?.ptr);
    try std.testing.expectEqual(@as(usize, 64), slot.?.len);
}

// Bug #37: end-to-end guard for the real overflow path. 100 x U+FDFA starts on
// the stack buffer (utf16_pos * 3 + 64 fits) but NFKD expands each one to 18
// UTF-16 units (1800 > the 1536-unit stack buffer), forcing the move to heap.
// Must succeed, keep the trailing word, and leak nothing.
test "tokenizeText stack-start normalization overflow does not leak (bug #37)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    for (0..100) |_| try text.appendSlice(gpa, "\u{FDFA}");
    try text.appendSlice(gpa, " tail");

    var cap: Capture = .{ .gpa = gpa, .tokens = .empty };
    defer {
        for (cap.tokens.items) |t| gpa.free(t);
        cap.tokens.deinit(gpa);
    }
    const rc = try tokenizeText(gpa, tok, text.items, null, &cap, captureTokenCallback);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);

    var found_tail = false;
    for (cap.tokens.items) |t| {
        if (std.mem.eql(u8, t, "tail")) found_tail = true;
    }
    try std.testing.expect(found_tail);
}

// Bug #38: `utf8_len + 64` / `utf8_len + 1` were evaluated in signed i32
// before widening, so a length near maxInt(i32) overflowed (panic in Debug,
// wrap in ReleaseFast), and grown capacities were cast back to i32 unchecked.
// `grownLen` widens first and rejects anything that no longer fits an i32
// ICU capacity. A real 2 GiB buffer is impractical in a unit test, so the
// boundaries are checked on the helper directly.
test "grownLen widens before adding and enforces the i32 ceiling (bug #38)" {
    const max_i32: i32 = std.math.maxInt(i32);

    // Ordinary growth.
    try std.testing.expectEqual(@as(usize, 64), try grownLen(0, 64));
    try std.testing.expectEqual(@as(usize, 101), try grownLen(100, 1));

    // Exactly at the ceiling is still representable as an i32 capacity...
    try std.testing.expectEqual(@as(usize, std.math.maxInt(i32)), try grownLen(max_i32 - 64, 64));
    try std.testing.expectEqual(@as(usize, std.math.maxInt(i32)), try grownLen(max_i32 - 1, 1));

    // ...one unit past it is rejected (the old i32 addition overflowed here).
    try std.testing.expectError(error.TextTooLarge, grownLen(max_i32 - 63, 64));
    try std.testing.expectError(error.TextTooLarge, grownLen(max_i32, 1));
    try std.testing.expectError(error.TextTooLarge, grownLen(max_i32, 64));

    // A negative length is never valid input for a size computation.
    try std.testing.expectError(error.TextTooLarge, grownLen(-1, 64));
}

// Bug #38: the rewritten sizing in the real paths still produces correct
// output (UTF-8 conversion capacity `utf8_len + 1` and the overflow retry).
test "transliterateString sizing stays correct after i32 hardening (bug #38)" {
    const gpa = std.testing.allocator;

    const out = try transliterateString(gpa, "ABCD", "Any-Name"); // forces the grow-retry
    defer gpa.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "LATIN CAPITAL LETTER A") != null);

    const cafe = try transliterateString(gpa, "Café", rules.ICU_RULE_DEFAULT);
    defer gpa.free(cafe);
    try std.testing.expectEqualStrings("cafe", cafe);
}

// Bug #40: tokenizeText used to decode every valid document twice
// (std.unicode.utf8ToUtf16Le, then buildByteOffsetMap re-decoding the whole
// string) and kept two copies of the same tolerant decode loop. The single
// remaining converter must therefore be an exact stand-in for the std
// converter on valid UTF-8 AND produce the byte-offset map the removed
// function did. This differential test checks both against independent
// references, across ASCII-only, mixed-width, astral and >512-byte inputs
// (so the ASCII fast path, the multi-byte path and the heap-sized buffers are
// all exercised).
fn expectConverterMatchesReference(gpa: std.mem.Allocator, text: []const u8) !void {
    const cap = text.len * 2 + 1; // same sizing as tokenizeText's req_u16_cap
    const got_u16 = try gpa.alloc(c.UChar, cap);
    defer gpa.free(got_u16);
    const got_map = try gpa.alloc(i32, cap);
    defer gpa.free(got_map);
    const want_u16 = try gpa.alloc(c.UChar, cap);
    defer gpa.free(want_u16);

    const n = convertUtf8ToUtf16Tolerant(got_u16, got_map, text);
    const want_n = try std.unicode.utf8ToUtf16Le(want_u16, text);
    try std.testing.expectEqual(want_n, n);
    try std.testing.expectEqualSlices(c.UChar, want_u16[0..want_n], got_u16[0..n]);

    // Reference map: walk the codepoints; every UTF-16 unit of a codepoint
    // maps to that codepoint's first UTF-8 byte.
    var it = (try std.unicode.Utf8View.init(text)).iterator();
    var u: usize = 0;
    var byte_off: usize = 0;
    while (it.nextCodepointSlice()) |cp_bytes| {
        const cp = try std.unicode.utf8Decode(cp_bytes);
        const units: usize = if (cp <= 0xFFFF) 1 else 2;
        for (0..units) |k| {
            try std.testing.expectEqual(@as(i32, @intCast(byte_off)), got_map[u + k]);
        }
        u += units;
        byte_off += cp_bytes.len;
    }
    try std.testing.expectEqual(n, u);
}

test "convertUtf8ToUtf16Tolerant matches std converter and offset map on valid UTF-8 (bug #40)" {
    const gpa = std.testing.allocator;

    try expectConverterMatchesReference(gpa, "");
    try expectConverterMatchesReference(gpa, "hello world");
    try expectConverterMatchesReference(gpa, "日本語のテスト");
    try expectConverterMatchesReference(gpa, "héllo wörld Ελληνικά русский");
    try expectConverterMatchesReference(gpa, "a🌍b😀c🎉"); // surrogate pairs between ASCII
    try expectConverterMatchesReference(gpa, "🌍"); // astral char alone, 4 bytes -> 2 units

    // > 512 bytes: forces the heap-sized path and a long ASCII run broken by
    // multi-byte characters.
    var big: std.ArrayList(u8) = .empty;
    defer big.deinit(gpa);
    for (0..40) |_| try big.appendSlice(gpa, "ascii run of plain text, ");
    try big.appendSlice(gpa, "é");
    for (0..40) |_| try big.appendSlice(gpa, "more ascii text ");
    try big.appendSlice(gpa, "🌍 tail");
    try std.testing.expect(big.items.len > 512);
    try expectConverterMatchesReference(gpa, big.items);
}

test "convertUtf8ToUtf16Tolerant tolerates malformed input and keeps offsets (bug #40)" {
    var u16buf: [32]c.UChar = undefined;
    var map: [32]i32 = undefined;

    // A lone byte that cannot start a sequence keeps its byte value as the
    // codepoint (pre-existing behavior, relied on by test_malformed_utf8.sql).
    var n = convertUtf8ToUtf16Tolerant(&u16buf, &map, "a\xFFb");
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualSlices(c.UChar, &.{ 'a', 0x00FF, 'b' }, u16buf[0..n]);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1, 2 }, map[0..n]);

    // Truncated 3-byte sequence at end of input: one U+FFFD for the stub
    // (std's utf8Decode would assert on the short slice).
    n = convertUtf8ToUtf16Tolerant(&u16buf, &map, "x\xE2\x82");
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualSlices(c.UChar, &.{ 'x', 0xFFFD }, u16buf[0..n]);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1 }, map[0..n]);

    // Truncated 2-byte and 4-byte leads at end of input behave the same way.
    n = convertUtf8ToUtf16Tolerant(&u16buf, &map, "y\xC3");
    try std.testing.expectEqualSlices(c.UChar, &.{ 'y', 0xFFFD }, u16buf[0..n]);
    n = convertUtf8ToUtf16Tolerant(&u16buf, &map, "z\xF0\x9F\x8C");
    try std.testing.expectEqualSlices(c.UChar, &.{ 'z', 0xFFFD }, u16buf[0..n]);

    // Lead byte whose continuation bytes are invalid: the whole lead-sized
    // span (here 3 bytes) collapses to one U+FFFD, as before, and the next
    // character's offset stays exact.
    n = convertUtf8ToUtf16Tolerant(&u16buf, &map, "\xE2\x41\x41q");
    try std.testing.expectEqualSlices(c.UChar, &.{ 0xFFFD, 'q' }, u16buf[0..n]);
    try std.testing.expectEqualSlices(i32, &.{ 0, 3 }, map[0..n]);

    // Valid astral char after ASCII: both surrogate units map to byte 1.
    n = convertUtf8ToUtf16Tolerant(&u16buf, &map, "x\u{1F30D}y");
    try std.testing.expectEqual(@as(usize, 4), n);
    try std.testing.expectEqualSlices(c.UChar, &.{ 'x', 0xD83C, 0xDF0D, 'y' }, u16buf[0..n]);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1, 1, 5 }, map[0..n]);
}

test "convertUtf8ToUtf16Tolerant never writes past either output (bug #40)" {
    var u16buf: [3]c.UChar = undefined;
    var map: [8]i32 = undefined;

    // The astral char needs 2 units but only 1 remains: stop cleanly, in
    // bounds, without a half-written pair.
    var n = convertUtf8ToUtf16Tolerant(&u16buf, &map, "ab\u{1F30D}");
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualSlices(c.UChar, &.{ 'a', 'b' }, u16buf[0..n]);

    // A map shorter than the UTF-16 buffer bounds the ASCII fast path too.
    var wide: [8]c.UChar = undefined;
    var short_map: [2]i32 = undefined;
    n = convertUtf8ToUtf16Tolerant(&wide, &short_map, "abcd");
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1 }, &short_map);
}

// Bug #39: CacheMutex.lock must be infallible (a failing Thread.yield used to
// abort tokenizeText with SQLITE_ERROR) and still provide mutual exclusion.
// `m.lock();` below compiles only if lock() returns void — had it stayed an
// error union, the discarded error would be a compile error. The counter is a
// plain (non-atomic) usize, so any lost update from a broken lock shows up as
// a wrong total.
test "CacheMutex is infallible and provides mutual exclusion (bug #39)" {
    const Shared = struct {
        mutex: CacheMutex = .{},
        counter: usize = 0,

        fn worker(self: *@This(), iterations: usize) void {
            for (0..iterations) |_| {
                self.mutex.lock();
                // Deliberately non-atomic read-modify-write inside the lock.
                const v = self.counter;
                std.atomic.spinLoopHint();
                self.counter = v + 1;
                self.mutex.unlock();
            }
        }
    };

    var shared: Shared = .{};
    const n_threads = 8;
    const iterations = 5000;

    var threads: [n_threads]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, Shared.worker, .{ &shared, iterations });
    }
    for (threads) |t| t.join();

    try std.testing.expectEqual(@as(usize, n_threads * iterations), shared.counter);
    // Lock is released at the end: an uncontended acquire succeeds at once.
    shared.mutex.lock();
    shared.mutex.unlock();
}

// Bug #39: end-to-end — the infallible lock sits on the query-time
// override-locale path of tokenizeText. Alternating overrides force cache
// misses and evictions while threads contend for the lock; every call must
// succeed (no spurious SQLITE_ERROR from the lock) and nothing may leak.
test "concurrent override-locale tokenizeText contends on the cache lock (bug #39)" {
    const gpa = std.testing.allocator;

    const tok = try IcuTokenizer.create(gpa, "");
    defer tok.destroy(gpa);

    var errors: std.atomic.Value(usize) = .init(0);
    const Ctx = struct {
        tokenizer: *IcuTokenizer,
        errors: *std.atomic.Value(usize),
        fn worker(self: @This(), first_override: []const u8, second_override: []const u8) void {
            for (0..10) |i| {
                const loc = if (i % 2 == 0) first_override else second_override;
                const rc = tokenizeText(
                    std.heap.c_allocator,
                    self.tokenizer,
                    "русский текст 日本語のテスト text",
                    loc,
                    null,
                    dummyTokenCallback,
                ) catch c.SQLITE_ERROR;
                if (rc != c.SQLITE_OK) _ = self.errors.fetchAdd(1, .monotonic);
            }
        }
    };

    var threads: [6]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        const a: []const u8 = if (i % 2 == 0) "ru" else "ja";
        const b: []const u8 = if (i % 2 == 0) "ja" else "ru";
        t.* = try std.Thread.spawn(.{}, Ctx.worker, .{ Ctx{ .tokenizer = tok, .errors = &errors }, a, b });
    }
    for (threads) |t| t.join();
    try std.testing.expectEqual(@as(usize, 0), errors.load(.monotonic));
}

// Bug #41 (1/2): isValidLocaleLanguage compared the bare language subtag with
// the FULL identifiers from uloc_getAvailable ("en_US", "kok_IN", ...), so a
// language ICU lists only under regional identifiers was rejected as invalid.
// The comparison is now on each entry's own language subtag. A real ICU build
// cannot be made to omit a bare entry, so the matcher is tested directly.
test "localeEntryHasLanguage matches the language subtag, not a string prefix (bug #41)" {
    // Bare and regional identifiers of the same language.
    try std.testing.expect(localeEntryHasLanguage("en", "en"));
    try std.testing.expect(localeEntryHasLanguage("en_US", "en"));
    try std.testing.expect(localeEntryHasLanguage("zh_Hans_CN", "zh"));
    try std.testing.expect(localeEntryHasLanguage("en-US", "en"));

    // The regional-only case from the bug: no bare "kok" entry exists.
    try std.testing.expect(localeEntryHasLanguage("kok_IN", "kok"));

    // A string prefix that is not the whole language subtag must not match.
    try std.testing.expect(!localeEntryHasLanguage("kok_IN", "ko"));
    try std.testing.expect(!localeEntryHasLanguage("kok", "ko"));
    try std.testing.expect(!localeEntryHasLanguage("en_US", "e"));
    try std.testing.expect(!localeEntryHasLanguage("fr_FR", "en"));
    try std.testing.expect(!localeEntryHasLanguage("", "en"));
}

test "isValidLocaleLanguage accepts real languages and rejects typos (bug #41)" {
    const valid = [_][:0]const u8{ "", "en", "en_US", "fr", "fr_CA", "de_DE", "es", "ja", "zh_Hans_CN", "ru_RU", "kok", "C" };
    for (valid) |loc| {
        try std.testing.expect(isValidLocaleLanguage(loc.ptr));
    }
    const invalid = [_][:0]const u8{ "xx_YY", "zzz", "qq", "notalocale" };
    for (invalid) |loc| {
        try std.testing.expect(!isValidLocaleLanguage(loc.ptr));
    }
}

// Bug #41 (2/2) + bugs #15/#19: fillPositionMap is the position-map algorithm
// extracted from tokenizeText. The tests pin its exact output, including the
// case #41 optimizes (no normalized spaces -> original text not scanned).
fn u16lit(comptime s: []const u8) [s.len]c.UChar {
    var out: [s.len]c.UChar = undefined;
    for (s, 0..) |b, i| out[i] = b;
    return out;
}

test "fillPositionMap without spaces scales proportionally (bug #41)" {
    // Ligature-like 1 -> 2 expansion, no spaces anywhere: the fast path that
    // skips the original-text space scan must still map exactly.
    const orig = [_]c.UChar{0xFB01}; // U+FB01 (fi ligature)
    const norm = u16lit("fi");
    var pm: [norm.len + 1]i32 = undefined;
    fillPositionMap(&pm, &norm, &orig);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1, 1 }, &pm);

    // Identity mapping for a space-free word.
    const word = u16lit("hello");
    var pm2: [word.len + 1]i32 = undefined;
    fillPositionMap(&pm2, &word, &word);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1, 2, 3, 4, 5 }, &pm2);

    // Empty text.
    var pm3: [1]i32 = undefined;
    fillPositionMap(&pm3, &.{}, &.{});
    try std.testing.expectEqualSlices(i32, &.{0}, &pm3);

    // Space-free normalized text from a NON-empty original that contains
    // spaces (original longer than normalized): spaces in the original must
    // not influence the result when there are no normalized anchors.
    const orig_sp = u16lit("a b");
    const norm_nosp = u16lit("ab");
    var pm4: [norm_nosp.len + 1]i32 = undefined;
    fillPositionMap(&pm4, &norm_nosp, &orig_sp);
    try std.testing.expectEqualSlices(i32, &.{ 0, 2, 3 }, &pm4);
}

test "fillPositionMap anchors on whitespace and end-pairs phantom spaces (bugs #15/#19, #41)" {
    // 1:1 text with spaces maps to itself (whitespace anchors are exact).
    const same = u16lit("ab cd");
    var pm: [same.len + 1]i32 = undefined;
    fillPositionMap(&pm, &same, &same);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1, 2, 3, 4, 5 }, &pm);

    // Phantom spaces: the source has one real space, but expansion of the
    // placeholder 'F' inserted two more in the normalized text. The two
    // phantom (leading) normalized spaces are skipped; the LAST normalized
    // space pairs with the real one, so the trailing word keeps its range.
    //   orig: x F y _ z            (5 units, space at 3)
    //   norm: x a _ b _ y _ z      (8 units, spaces at 2, 4, 6)
    const orig = u16lit("xFy z");
    const norm = u16lit("xa b y z");
    var pm2: [norm.len + 1]i32 = undefined;
    fillPositionMap(&pm2, &norm, &orig);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1, 1, 2, 2, 3, 3, 4, 5 }, &pm2);
    // The final word "z" (norm 7..8) maps to exactly orig 4..5.
    try std.testing.expectEqual(@as(i32, 4), pm2[7]);
    try std.testing.expectEqual(@as(i32, 5), pm2[8]);
}
