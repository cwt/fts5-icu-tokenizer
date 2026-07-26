const std = @import("std");
const builtin = @import("builtin");

const icu_funcs = [_][]const u8{
    "ubrk_open",
    "ubrk_close",
    "ubrk_clone",
    "ubrk_setText",
    "ubrk_first",
    "ubrk_next",
    "ubrk_getRuleStatus",
    "u_strFromUTF8",
    "u_strToUTF8WithSub",
    "u_strToUTF8",
    "utrans_openU",
    "utrans_close",
    "utrans_transUChars",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode") orelse .ReleaseFast;

    const locale = b.option([]const u8, "locale", "Tokenizer locale (e.g. ja, zh, th, ar, ru, he, el)") orelse "";
    const api_version = b.option([]const u8, "api_version", "FTS5 API version (v1 or v2)") orelse "v2";
    const version_str = "6.0.3";

    const lto_enabled = !target.result.os.tag.isDarwin();
    const is_macos = builtin.os.tag.isDarwin();

    // Detect ICU major version on Linux for linker symbol aliases
    const icu_ver: u32 = if (!is_macos) blk: {
        const result = b.run(&.{ "sh", "-c", "grep -o '#define U_ICU_VERSION_MAJOR_NUM [0-9]*' /usr/include/unicode/uvernum.h | grep -o '[0-9]*'" });
        break :blk std.fmt.parseInt(u32, std.mem.trim(u8, result, " \n\r"), 10) catch 0;
    } else 0;

    // On Linux with versioned ICU symbols, generate assembly aliases
    const icu_alias_lp = if (icu_ver > 0) blk: {
        var buf: [4096]u8 = undefined;
        var pos: usize = 0;
        for (icu_funcs) |f| {
            const line = std.fmt.bufPrint(buf[pos..], ".globl {s}\n.type {s}, @function\n{s}:\n\tb {s}_{d}\n", .{ f, f, f, f, icu_ver }) catch unreachable;
            pos += line.len;
        }
        const alias_step = b.addWriteFile("icu_aliases.s", buf[0..pos]);
        break :blk alias_step.getDirectory().path(b, "icu_aliases.s");
    } else null;

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

    translate_c.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    translate_c.addSystemIncludePath(.{ .cwd_relative = "/usr/local/include" });
    if (is_macos) {
        translate_c.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/include" });
        translate_c.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/icu4c/include" });
    }

    const c_mod = translate_c.createModule();
    c_mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    c_mod.addSystemIncludePath(.{ .cwd_relative = "/usr/local/include" });
    if (is_macos) {
        c_mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/lib" });
        c_mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/icu4c/lib" });
    } else {
        c_mod.addLibraryPath(.{ .cwd_relative = "/lib64" });
        c_mod.addLibraryPath(.{ .cwd_relative = "/usr/lib64" });
    }
    c_mod.linkSystemLibrary("sqlite3", .{});
    c_mod.linkSystemLibrary("icui18n", .{});
    c_mod.linkSystemLibrary("icuuc", .{});
    c_mod.linkSystemLibrary("icudata", .{});
    c_mod.link_libc = true;
    if (icu_alias_lp) |lp| c_mod.addAssemblyFile(lp);

    const c_icu_mod = b.createModule(.{
        .root_source_file = b.path("src/c_icu.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
        },
    });

    const linkModule = struct {
        fn apply(mod: *std.Build.Module, macos: bool) void {
            mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
            mod.addSystemIncludePath(.{ .cwd_relative = "/usr/local/include" });
            if (macos) {
                mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/lib" });
                mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/icu4c/lib" });
            } else {
                mod.addLibraryPath(.{ .cwd_relative = "/lib64" });
                mod.addLibraryPath(.{ .cwd_relative = "/usr/lib64" });
            }
            mod.linkSystemLibrary("sqlite3", .{ .needed = true });
            mod.linkSystemLibrary("icui18n", .{ .needed = true });
            mod.linkSystemLibrary("icuuc", .{ .needed = true });
            mod.linkSystemLibrary("icudata", .{ .needed = true });
            mod.link_libc = true;
        }
    }.apply;

    const configureArtifact = struct {
        fn apply(comp: *std.Build.Step.Compile, enable_lto: bool) void {
            comp.linker_allow_shlib_undefined = true;
            if (enable_lto) comp.lto = .thin;
        }
    }.apply;

    // Root module for FTS5 ICU universal tokenizer library (v2)
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/fts5_icu.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
            .{ .name = "c_icu", .module = c_icu_mod },
            .{ .name = "build_options", .module = options_mod },
        },
    });
    linkModule(root_module, is_macos);

    // Dynamic library build (fts5_icu)
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = if (locale.len > 0) b.fmt("fts5_icu_{s}", .{locale}) else "fts5_icu",
        .root_module = root_module,
    });
    configureArtifact(lib, lto_enabled);
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
            .{ .name = "c_icu", .module = c_icu_mod },
            .{ .name = "build_options", .module = legacy_options.createModule() },
        },
    });
    linkModule(legacy_root_module, is_macos);

    const lib_legacy = b.addLibrary(.{
        .linkage = .dynamic,
        .name = if (locale.len > 0) b.fmt("fts5_icu_{s}_legacy", .{locale}) else "fts5_icu_legacy",
        .root_module = legacy_root_module,
    });
    configureArtifact(lib_legacy, lto_enabled);
    b.installArtifact(lib_legacy);

    // Build locale-specific libraries
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
                .{ .name = "c_icu", .module = c_icu_mod },
                .{ .name = "build_options", .module = loc_options.createModule() },
            },
        });
        linkModule(loc_root, is_macos);

        const loc_lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = b.fmt("fts5_icu_{s}", .{loc}),
            .root_module = loc_root,
        });
        configureArtifact(loc_lib, lto_enabled);
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
                .{ .name = "c_icu", .module = c_icu_mod },
                .{ .name = "build_options", .module = loc_leg_options.createModule() },
            },
        });
        linkModule(loc_leg_root, is_macos);

        const loc_leg_lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = b.fmt("fts5_icu_{s}_legacy", .{loc}),
            .root_module = loc_leg_root,
        });
        configureArtifact(loc_leg_lib, lto_enabled);
        b.installArtifact(loc_leg_lib);
    }

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = root_module,
    });
    configureArtifact(unit_tests, false);

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
            .{ .name = "c_icu", .module = c_icu_mod },
        },
    });
    linkModule(translit_mod, is_macos);

    const exe_translit = b.addExecutable(.{
        .name = "test_transliterator",
        .root_module = translit_mod,
    });
    configureArtifact(exe_translit, lto_enabled);

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
            .{ .name = "c_icu", .module = c_icu_mod },
        },
    });
    linkModule(locale_tests_mod, is_macos);

    const exe_locale_tests = b.addExecutable(.{
        .name = "locale_specific_tests",
        .root_module = locale_tests_mod,
    });
    configureArtifact(exe_locale_tests, lto_enabled);

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
            .{ .name = "c_icu", .module = c_icu_mod },
        },
    });
    linkModule(tok_test_mod, is_macos);

    const exe_tok_test = b.addExecutable(.{
        .name = "test_locale_tokenizer",
        .root_module = tok_test_mod,
    });
    configureArtifact(exe_tok_test, lto_enabled);

    const run_tok_test = b.addRunArtifact(exe_tok_test);
    const run_tok_test_step = b.step("run-tokenizer-test", "Run locale tokenizer test");
    run_tok_test_step.dependOn(&run_tok_test.step);
}
