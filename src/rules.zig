const std = @import("std");

pub const ICU_RULE_BASE = "NFKD; ";
pub const ICU_RULE_JA = ICU_RULE_BASE ++ "Katakana-Hiragana; Lower; NFKC";
pub const ICU_RULE_ZH = ICU_RULE_BASE ++ "Traditional-Simplified; Lower; NFKC";
pub const ICU_RULE_TH = ICU_RULE_BASE ++ "Lower; NFKC";
pub const ICU_RULE_KO = ICU_RULE_BASE ++ "Lower; NFKC";
pub const ICU_RULE_AR = ICU_RULE_BASE ++ "Arabic-Latin; Lower; NFKC";
pub const ICU_RULE_RU = ICU_RULE_BASE ++ "Cyrillic-Latin; Lower; NFKC";
pub const ICU_RULE_HE = ICU_RULE_BASE ++ "Hebrew-Latin; Lower; NFKC";
pub const ICU_RULE_EL = ICU_RULE_BASE ++ "Greek-Latin; Lower; NFKC";
pub const ICU_RULE_DEFAULT = ICU_RULE_BASE ++ "Arabic-Latin; Cyrillic-Latin; Hebrew-Latin; " ++
    "Greek-Latin; Latin-ASCII; " ++
    "Lower; NFKC; Traditional-Simplified; " ++
    "Katakana-Hiragana";

pub const LocaleInfo = struct {
    rules: []const u8,
    suffix: []const u8,
    tokenizer_name: []const u8,
};

pub fn getLocaleInfo(locale: []const u8) LocaleInfo {
    if (locale.len >= 2) {
        const prefix = locale[0..2];
        if (std.mem.eql(u8, prefix, "ja") or std.mem.eql(u8, prefix, "jp")) return .{ .rules = ICU_RULE_JA, .suffix = "_ja", .tokenizer_name = "icu_ja" };
        if (std.mem.eql(u8, prefix, "zh") or std.mem.eql(u8, prefix, "cn")) return .{ .rules = ICU_RULE_ZH, .suffix = "_zh", .tokenizer_name = "icu_zh" };
        if (std.mem.eql(u8, prefix, "th")) return .{ .rules = ICU_RULE_TH, .suffix = "_th", .tokenizer_name = "icu_th" };
        if (std.mem.eql(u8, prefix, "ko") or std.mem.eql(u8, prefix, "kr")) return .{ .rules = ICU_RULE_KO, .suffix = "_ko", .tokenizer_name = "icu_ko" };
        if (std.mem.eql(u8, prefix, "ar")) return .{ .rules = ICU_RULE_AR, .suffix = "_ar", .tokenizer_name = "icu_ar" };
        if (std.mem.eql(u8, prefix, "ru")) return .{ .rules = ICU_RULE_RU, .suffix = "_ru", .tokenizer_name = "icu_ru" };
        if (std.mem.eql(u8, prefix, "he") or std.mem.eql(u8, prefix, "iw")) return .{ .rules = ICU_RULE_HE, .suffix = "_he", .tokenizer_name = "icu_he" };
        if (std.mem.eql(u8, prefix, "el") or std.mem.eql(u8, prefix, "gr")) return .{ .rules = ICU_RULE_EL, .suffix = "_el", .tokenizer_name = "icu_el" };
    }
    return .{ .rules = ICU_RULE_DEFAULT, .suffix = "", .tokenizer_name = "icu" };
}

pub fn getRulesForLocale(locale: []const u8) []const u8 {
    return getLocaleInfo(locale).rules;
}

pub fn getSuffixForLocale(locale: []const u8) []const u8 {
    return getLocaleInfo(locale).suffix;
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
    try std.testing.expectEqualStrings("_ja", info_ja.suffix);
    try std.testing.expectEqualStrings("icu_ja", info_ja.tokenizer_name);
}
