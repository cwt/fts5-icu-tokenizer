const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const locale = b.option([]const u8, "locale", "Tokenizer locale (e.g. ja, zh, th, ar, ru, he, el)") orelse "";
    const api_version = b.option([]const u8, "api_version", "FTS5 API version (v1 or v2)") orelse "v2";
    const version_str = "6.0.1";

    // Build options module for default library
    const options = b.addOptions();
    options.addOption([]const u8, "locale", locale);
    options.addOption([]const u8, "api_version", api_version);
    options.addOption([]const u8, "version", version_str);
    const options_mod = options.createModule();

    // Translate-C step for SQLite and ICU headers
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c_includes.h"),
        .target = target,
        .optimize = optimize,
    });

    // Add include paths for system / Homebrew dependencies
    translate_c.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/include" });
    translate_c.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/icu4c/include" });
    translate_c.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    translate_c.addSystemIncludePath(.{ .cwd_relative = "/usr/local/include" });

    const c_mod = translate_c.createModule();
    c_mod.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/include" });
    c_mod.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/icu4c/include" });
    c_mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/lib" });
    c_mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/icu4c/lib" });
    c_mod.linkSystemLibrary("sqlite3", .{});
    c_mod.linkSystemLibrary("icui18n", .{});
    c_mod.linkSystemLibrary("icuuc", .{});
    c_mod.linkSystemLibrary("icudata", .{});
    c_mod.link_libc = true;

    // Helper for user modules
    const linkModule = struct {
        fn apply(mod: *std.Build.Module) void {
            mod.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/include" });
            mod.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/icu4c/include" });
            mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/lib" });
            mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/icu4c/lib" });
            mod.linkSystemLibrary("sqlite3", .{});
            mod.linkSystemLibrary("icui18n", .{});
            mod.linkSystemLibrary("icuuc", .{});
            mod.linkSystemLibrary("icudata", .{});
            mod.link_libc = true;
        }
    }.apply;

    // Root module for FTS5 ICU universal tokenizer library (v2)
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/fts5_icu.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
            .{ .name = "build_options", .module = options_mod },
        },
    });
    linkModule(root_module);

    // Dynamic library build (fts5_icu)
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = if (locale.len > 0) b.fmt("fts5_icu_{s}", .{locale}) else "fts5_icu",
        .root_module = root_module,
    });
    lib.linker_allow_shlib_undefined = true;

    b.installArtifact(lib);

    // Root module for FTS5 ICU universal tokenizer library (v1 legacy)
    const legacy_options = b.addOptions();
    legacy_options.addOption([]const u8, "locale", locale);
    legacy_options.addOption([]const u8, "api_version", "v1");
    legacy_options.addOption([]const u8, "version", version_str);

    const legacy_root_module = b.createModule(.{
        .root_source_file = b.path("src/fts5_icu.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
            .{ .name = "build_options", .module = legacy_options.createModule() },
        },
    });
    linkModule(legacy_root_module);

    const lib_legacy = b.addLibrary(.{
        .linkage = .dynamic,
        .name = if (locale.len > 0) b.fmt("fts5_icu_{s}_legacy", .{locale}) else "fts5_icu_legacy",
        .root_module = legacy_root_module,
    });
    lib_legacy.linker_allow_shlib_undefined = true;
    b.installArtifact(lib_legacy);

    // Build locale-specific libraries (libfts5_icu_ja, libfts5_icu_zh, etc. both v2 and legacy v1)
    const locales = [_][]const u8{ "ja", "zh", "th", "ko", "ar", "ru", "he", "el" };
    for (locales) |loc| {
        // v2
        const loc_options = b.addOptions();
        loc_options.addOption([]const u8, "locale", loc);
        loc_options.addOption([]const u8, "api_version", "v2");
        loc_options.addOption([]const u8, "version", version_str);

        const loc_root = b.createModule(.{
            .root_source_file = b.path("src/fts5_icu.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c", .module = c_mod },
                .{ .name = "build_options", .module = loc_options.createModule() },
            },
        });
        linkModule(loc_root);

        const loc_lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = b.fmt("fts5_icu_{s}", .{loc}),
            .root_module = loc_root,
        });
        loc_lib.linker_allow_shlib_undefined = true;
        b.installArtifact(loc_lib);

        // v1 legacy
        const loc_leg_options = b.addOptions();
        loc_leg_options.addOption([]const u8, "locale", loc);
        loc_leg_options.addOption([]const u8, "api_version", "v1");
        loc_leg_options.addOption([]const u8, "version", version_str);

        const loc_leg_root = b.createModule(.{
            .root_source_file = b.path("src/fts5_icu.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c", .module = c_mod },
                .{ .name = "build_options", .module = loc_leg_options.createModule() },
            },
        });
        linkModule(loc_leg_root);

        const loc_leg_lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = b.fmt("fts5_icu_{s}_legacy", .{loc}),
            .root_module = loc_leg_root,
        });
        loc_leg_lib.linker_allow_shlib_undefined = true;
        b.installArtifact(loc_leg_lib);
    }

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = root_module,
    });
    unit_tests.linker_allow_shlib_undefined = true;

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Test executables: test_transliterator
    const translit_mod = b.createModule(.{
        .root_source_file = b.path("src/test_transliterator.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
        },
    });
    linkModule(translit_mod);

    const exe_translit = b.addExecutable(.{
        .name = "test_transliterator",
        .root_module = translit_mod,
    });
    exe_translit.linker_allow_shlib_undefined = true;

    const run_translit = b.addRunArtifact(exe_translit);
    const run_translit_step = b.step("run-transliterator", "Run ICU transliterator test");
    run_translit_step.dependOn(&run_translit.step);

    // Test executables: locale_specific_tests
    const locale_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/locale_specific_tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
        },
    });
    linkModule(locale_tests_mod);

    const exe_locale_tests = b.addExecutable(.{
        .name = "locale_specific_tests",
        .root_module = locale_tests_mod,
    });
    exe_locale_tests.linker_allow_shlib_undefined = true;

    const run_locale_tests = b.addRunArtifact(exe_locale_tests);
    const run_locale_tests_step = b.step("run-locale-tests", "Run locale-specific transliterator tests");
    run_locale_tests_step.dependOn(&run_locale_tests.step);

    // Test executables: test_locale_tokenizer
    const tok_test_mod = b.createModule(.{
        .root_source_file = b.path("src/test_locale_tokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
        },
    });
    linkModule(tok_test_mod);

    const exe_tok_test = b.addExecutable(.{
        .name = "test_locale_tokenizer",
        .root_module = tok_test_mod,
    });
    exe_tok_test.linker_allow_shlib_undefined = true;

    const run_tok_test = b.addRunArtifact(exe_tok_test);
    const run_tok_test_step = b.step("run-tokenizer-test", "Run locale tokenizer test");
    run_tok_test_step.dependOn(&run_tok_test.step);
}
