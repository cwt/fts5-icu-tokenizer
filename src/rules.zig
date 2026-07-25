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

pub fn getRulesForLocale(locale: []const u8) []const u8 {
    if (locale.len >= 2) {
        const prefix = locale[0..2];
        if (std.mem.eql(u8, prefix, "ja") or std.mem.eql(u8, prefix, "jp")) {
            return ICU_RULE_JA;
        } else if (std.mem.eql(u8, prefix, "zh") or std.mem.eql(u8, prefix, "cn")) {
            return ICU_RULE_ZH;
        } else if (std.mem.eql(u8, prefix, "th")) {
            return ICU_RULE_TH;
        } else if (std.mem.eql(u8, prefix, "ko") or std.mem.eql(u8, prefix, "kr")) {
            return ICU_RULE_KO;
        } else if (std.mem.eql(u8, prefix, "ar")) {
            return ICU_RULE_AR;
        } else if (std.mem.eql(u8, prefix, "ru")) {
            return ICU_RULE_RU;
        } else if (std.mem.eql(u8, prefix, "he") or std.mem.eql(u8, prefix, "iw")) {
            return ICU_RULE_HE;
        } else if (std.mem.eql(u8, prefix, "el") or std.mem.eql(u8, prefix, "gr")) {
            return ICU_RULE_EL;
        }
    }
    return ICU_RULE_DEFAULT;
}

pub fn getSuffixForLocale(locale: []const u8) []const u8 {
    if (locale.len >= 2) {
        const prefix = locale[0..2];
        if (std.mem.eql(u8, prefix, "ja") or std.mem.eql(u8, prefix, "jp")) return "_ja";
        if (std.mem.eql(u8, prefix, "zh") or std.mem.eql(u8, prefix, "cn")) return "_zh";
        if (std.mem.eql(u8, prefix, "th")) return "_th";
        if (std.mem.eql(u8, prefix, "ko") or std.mem.eql(u8, prefix, "kr")) return "_ko";
        if (std.mem.eql(u8, prefix, "ar")) return "_ar";
        if (std.mem.eql(u8, prefix, "ru")) return "_ru";
        if (std.mem.eql(u8, prefix, "he") or std.mem.eql(u8, prefix, "iw")) return "_he";
        if (std.mem.eql(u8, prefix, "el") or std.mem.eql(u8, prefix, "gr")) return "_el";
    }
    return "";
}

pub fn getTokenizerNameForLocale(locale: []const u8) []const u8 {
    if (locale.len >= 2) {
        const prefix = locale[0..2];
        if (std.mem.eql(u8, prefix, "ja") or std.mem.eql(u8, prefix, "jp")) return "icu_ja";
        if (std.mem.eql(u8, prefix, "zh") or std.mem.eql(u8, prefix, "cn")) return "icu_zh";
        if (std.mem.eql(u8, prefix, "th")) return "icu_th";
        if (std.mem.eql(u8, prefix, "ko") or std.mem.eql(u8, prefix, "kr")) return "icu_ko";
        if (std.mem.eql(u8, prefix, "ar")) return "icu_ar";
        if (std.mem.eql(u8, prefix, "ru")) return "icu_ru";
        if (std.mem.eql(u8, prefix, "he") or std.mem.eql(u8, prefix, "iw")) return "icu_he";
        if (std.mem.eql(u8, prefix, "el") or std.mem.eql(u8, prefix, "gr")) return "icu_el";
    }
    return "icu";
}

test "rules mapping" {
    try std.testing.expectEqualStrings(ICU_RULE_JA, getRulesForLocale("ja"));
    try std.testing.expectEqualStrings(ICU_RULE_ZH, getRulesForLocale("zh-CN"));
    try std.testing.expectEqualStrings(ICU_RULE_DEFAULT, getRulesForLocale("en_US"));
}
