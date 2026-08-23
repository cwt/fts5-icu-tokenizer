const std = @import("std");

pub const ICU_RULE_BASE = "NFKD; ";
pub const ICU_RULE_LATIN_NORMALIZE = "Latin-ASCII; Lower; ";
pub const ICU_RULE_JA = ICU_RULE_BASE ++ "Hiragana-Katakana; Lower; NFKC";
pub const ICU_RULE_ZH = ICU_RULE_BASE ++ "Traditional-Simplified; Lower; NFKC";
pub const ICU_RULE_TH = ICU_RULE_BASE ++ "Lower; NFKC";
pub const ICU_RULE_KO = ICU_RULE_BASE ++ "Lower; NFKC";
pub const ICU_RULE_AR = ICU_RULE_BASE ++ "Arabic-Latin; " ++ ICU_RULE_LATIN_NORMALIZE ++ "NFKC";
pub const ICU_RULE_RU = ICU_RULE_BASE ++ "Russian-Latin/BGN; " ++ ICU_RULE_LATIN_NORMALIZE ++ "NFKC";
pub const ICU_RULE_HE = ICU_RULE_BASE ++ "Hebrew-Latin; " ++ ICU_RULE_LATIN_NORMALIZE ++ "NFKC";
pub const ICU_RULE_EL = ICU_RULE_BASE ++ "Greek-Latin; " ++ ICU_RULE_LATIN_NORMALIZE ++ "NFKC";
pub const ICU_RULE_DEFAULT = ICU_RULE_BASE ++ "Arabic-Latin; Russian-Latin/BGN; Hebrew-Latin; " ++
    "Greek-Latin; " ++ ICU_RULE_LATIN_NORMALIZE ++ "NFKC; Traditional-Simplified; " ++
    "Hiragana-Katakana";

pub const LocaleInfo = struct {
    rules: []const u8,
    tokenizer_name: []const u8,
};

// Case-insensitive equality for a language subtag.
fn langEql(a: []const u8, b: []const u8) bool {
    return a.len == b.len and std.ascii.eqlIgnoreCase(a, b);
}

pub fn getLocaleInfo(locale: []const u8) LocaleInfo {
    if (locale.len >= 2) {
        // Bug #21: match the FULL language subtag (up to '-', '_' or '@')
        // case-insensitively. The previous raw two-byte prefix compare was
        // case-sensitive ("JA_JP" fell through to DEFAULT while ICU itself
        // accepts that spelling) and unanchored ("kok"/Konkani matched ko,
        // "arn"/Mapudungun matched ar, "jam"/Jamaican Creole matched ja).
        const lang = locale[0 .. std.mem.indexOfAny(u8, locale, "-_@") orelse locale.len];
        if (langEql(lang, "ja") or langEql(lang, "jp")) return .{ .rules = ICU_RULE_JA, .tokenizer_name = "icu_ja" };
        if (langEql(lang, "zh") or langEql(lang, "cn")) return .{ .rules = ICU_RULE_ZH, .tokenizer_name = "icu_zh" };
        if (langEql(lang, "th")) return .{ .rules = ICU_RULE_TH, .tokenizer_name = "icu_th" };
        if (langEql(lang, "ko") or langEql(lang, "kr")) return .{ .rules = ICU_RULE_KO, .tokenizer_name = "icu_ko" };
        if (langEql(lang, "ar")) return .{ .rules = ICU_RULE_AR, .tokenizer_name = "icu_ar" };
        if (langEql(lang, "ru")) return .{ .rules = ICU_RULE_RU, .tokenizer_name = "icu_ru" };
        if (langEql(lang, "he") or langEql(lang, "iw")) return .{ .rules = ICU_RULE_HE, .tokenizer_name = "icu_he" };
        if (langEql(lang, "el") or langEql(lang, "gr")) return .{ .rules = ICU_RULE_EL, .tokenizer_name = "icu_el" };
    }
    return .{ .rules = ICU_RULE_DEFAULT, .tokenizer_name = "icu" };
}

pub fn getRulesForLocale(locale: []const u8) []const u8 {
    return getLocaleInfo(locale).rules;
}

pub fn getTokenizerNameForLocale(locale: []const u8) []const u8 {
    return getLocaleInfo(locale).tokenizer_name;
}

test "rules mapping" {
    try std.testing.expectEqualStrings(ICU_RULE_JA, getRulesForLocale("ja"));
    try std.testing.expectEqualStrings(ICU_RULE_ZH, getRulesForLocale("zh-CN"));
    try std.testing.expectEqualStrings(ICU_RULE_DEFAULT, getRulesForLocale("en_US"));

    const info_ja = getLocaleInfo("ja_JP");
    try std.testing.expectEqualStrings(ICU_RULE_JA, info_ja.rules);
    try std.testing.expectEqualStrings("icu_ja", info_ja.tokenizer_name);
}

// Bug #21: language matching must be case-insensitive (ICU locale IDs are)
// and anchored at the full subtag, so unrelated languages that merely start
// with the same two letters keep the universal rules.
test "rules mapping is case-insensitive and subtag-anchored (bug #21)" {
    // Case-insensitivity matches ICU's own canonicalization…
    try std.testing.expectEqualStrings(ICU_RULE_JA, getRulesForLocale("JA_JP"));
    try std.testing.expectEqualStrings(ICU_RULE_HE, getRulesForLocale("IW"));
    try std.testing.expectEqualStrings(ICU_RULE_EL, getRulesForLocale("Gr"));
    try std.testing.expectEqualStrings("icu_ja", getTokenizerNameForLocale("Ja"));

    // …while unanchored prefixes must not hijack unrelated languages.
    try std.testing.expectEqualStrings(ICU_RULE_DEFAULT, getRulesForLocale("kok")); // Konkani, not ko
    try std.testing.expectEqualStrings(ICU_RULE_DEFAULT, getRulesForLocale("arn")); // Mapudungun, not ar
    try std.testing.expectEqualStrings(ICU_RULE_DEFAULT, getRulesForLocale("jam")); // Jamaican Creole, not ja
    try std.testing.expectEqualStrings("icu", getTokenizerNameForLocale("kok"));
}

// Bug #14: Cyrillic-Latin (any variant, and the diacritic-strip post-filter)
// collapses щ/ш/с -> s and ж/з -> z. Russian-Latin/BGN keeps them distinct
// (борщ->borshch, шар->shar, жар->zhar) and is pure ASCII. Available as
// Russian-Latin/BGN on ICU 67 and later (plain Russian-Latin does not exist).
test "rules use Russian-Latin/BGN for Russian (bug #14)" {
    try std.testing.expect(std.mem.indexOf(u8, ICU_RULE_RU, "Russian-Latin/BGN") != null);
    try std.testing.expect(std.mem.indexOf(u8, ICU_RULE_DEFAULT, "Russian-Latin/BGN") != null);
    try std.testing.expect(std.mem.indexOf(u8, ICU_RULE_RU, "Cyrillic-Latin") == null);
    try std.testing.expect(std.mem.indexOf(u8, ICU_RULE_DEFAULT, "Cyrillic-Latin") == null);
}
