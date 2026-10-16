const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const OptimizeMode = std.builtin.OptimizeMode;
    const release_fast_mode: OptimizeMode = if (@hasField(OptimizeMode, "fast")) .fast else .ReleaseFast;
    const debug_mode: OptimizeMode = if (@hasField(OptimizeMode, "debug")) .debug else .Debug;
    const optimize = b.option(OptimizeMode, "optimize", "Optimization mode") orelse release_fast_mode;

    const locale = b.option([]const u8, "locale", "Tokenizer locale (e.g. ja, zh, th, ar, ru, he, el)") orelse "";
    const api_version = b.option([]const u8, "api_version", "FTS5 API version (v1 or v2)") orelse "v2";
    const version_str = "7.2.0";

    const lto_enabled = !target.result.os.tag.isDarwin();
    const is_macos = builtin.os.tag.isDarwin();

    // c_icu.zig reads U_ICU_VERSION_MAJOR_NUM from the translateC module at
    // comptime; tokenizer.zig also derives has_ubrk_clone that way.  No
    // build-time ICU version detection or assembly aliases are needed.

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

    // Bug #34: one helper for the include paths shared by the translate-C
    // step and its module (c_mod additionally gains the macOS paths, which
    // is harmless — extra -I entries — and more correct there).
    const addIncludes = struct {
        fn apply(step: anytype, macos: bool) void {
            step.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
            step.addSystemIncludePath(.{ .cwd_relative = "/usr/local/include" });
            if (macos) {
                step.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/include" });
                step.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/icu4c/include" });
            }
        }
    }.apply;
    addIncludes(translate_c, is_macos);

    const addLibraryPaths = struct {
        fn apply(mod: *std.Build.Module, builder: *std.Build, macos: bool) void {
            if (macos) {
                mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/lib" });
                mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/icu4c/lib" });
            } else {
                const candidates = [_][]const u8{
                    // Standard FHS & distro layouts (Alpine, Arch, Void, EL/Fedora, Slackware)
                    "/lib",
                    "/usr/lib",
                    "/usr/local/lib",
                    "/lib64",
                    "/usr/lib64",
                    "/usr/local/lib64",
                    // Debian / Ubuntu multiarch triplets
                    "/usr/lib/aarch64-linux-gnu",
                    "/usr/lib/x86_64-linux-gnu",
                    "/usr/lib/arm-linux-gnueabihf",
                    "/usr/lib/arm-linux-gnueabi",
                    "/usr/lib/i386-linux-gnu",
                    "/usr/lib/riscv64-linux-gnu",
                    "/usr/lib/powerpc64le-linux-gnu",
                    "/usr/lib/s390x-linux-gnu",
                    "/usr/lib/loongarch64-linux-gnu",
                    // Musl multiarch layouts
                    "/usr/lib/x86_64-linux-musl",
                    "/usr/lib/aarch64-linux-musl",
                    "/usr/lib/arm-linux-musleabihf",
                    "/usr/lib/riscv64-linux-musl",
                };
                for (candidates) |p| {
                    if (std.Io.Dir.accessAbsolute(builder.graph.io, p, .{})) |_| {
                        mod.addLibraryPath(.{ .cwd_relative = p });
                    } else |_| {}
                }
            }
        }
    }.apply;

    const c_mod = translate_c.createModule();
    addIncludes(c_mod, is_macos);
    addLibraryPaths(c_mod, b, is_macos);
    c_mod.linkSystemLibrary("sqlite3", .{});
    c_mod.linkSystemLibrary("icui18n", .{});
    c_mod.linkSystemLibrary("icuuc", .{});
    c_mod.linkSystemLibrary("icudata", .{});
    c_mod.link_libc = true;

    const c_icu_mod = b.createModule(.{
        .root_source_file = b.path("src/c_icu.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
        },
    });

    const linkModule = struct {
        fn apply(mod: *std.Build.Module, builder: *std.Build, macos: bool) void {
            // Bug #42: reuse addIncludes instead of duplicating /usr/include and /usr/local/include.
            addIncludes(mod, macos);
            addLibraryPaths(mod, builder, macos);
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

    // Bug #42: helper for building and installing a tokenizer shared library
    const addTokenizerLibrary = struct {
        fn apply(
            builder: *std.Build,
            name: []const u8,
            loc: []const u8,
            api_ver: []const u8,
            target_step: std.Build.ResolvedTarget,
            opt: OptimizeMode,
            c_m: *std.Build.Module,
            c_icu_m: *std.Build.Module,
            enable_lto: bool,
            macos: bool,
        ) void {
            const opts = builder.addOptions();
            opts.addOption([]const u8, "locale", loc);
            opts.addOption([]const u8, "api_version", api_ver);
            opts.addOption([]const u8, "version", version_str);

            const root_mod = builder.createModule(.{
                .root_source_file = builder.path("src/fts5_icu.zig"),
                .target = target_step,
                .optimize = opt,
                .imports = &.{
                    .{ .name = "c", .module = c_m },
                    .{ .name = "c_icu", .module = c_icu_m },
                    .{ .name = "build_options", .module = opts.createModule() },
                },
            });
            linkModule(root_mod, builder, macos);

            const dylib = builder.addLibrary(.{
                .linkage = .dynamic,
                .name = name,
                .root_module = root_mod,
            });
            configureArtifact(dylib, enable_lto);
            builder.installArtifact(dylib);
        }
    }.apply;

    // Dynamic library build (fts5_icu v2 and v1 legacy)
    const lib_name = if (locale.len > 0) b.fmt("fts5_icu_{s}", .{locale}) else "fts5_icu";
    addTokenizerLibrary(b, lib_name, locale, api_version, target, optimize, c_mod, c_icu_mod, lto_enabled, is_macos);

    const lib_legacy_name = if (locale.len > 0) b.fmt("fts5_icu_{s}_legacy", .{locale}) else "fts5_icu_legacy";
    addTokenizerLibrary(b, lib_legacy_name, locale, "v1", target, optimize, c_mod, c_icu_mod, lto_enabled, is_macos);

    // Build locale-specific libraries
    const locales = [_][]const u8{ "ja", "zh", "th", "ko", "ar", "ru", "he", "el" };
    for (locales) |loc| {
        // Bug #24: when -Dlocale names one of the loop locales, the
        // top-level conditional libraries above already produce
        // fts5_icu_<loc> and fts5_icu_<loc>_legacy; emitting them again
        // would compile each artifact twice and install both to the same
        // zig-out/lib path (last install silently wins).
        if (locale.len > 0 and std.mem.eql(u8, loc, locale)) continue;
        addTokenizerLibrary(b, b.fmt("fts5_icu_{s}", .{loc}), loc, "v2", target, optimize, c_mod, c_icu_mod, lto_enabled, is_macos);
        addTokenizerLibrary(b, b.fmt("fts5_icu_{s}_legacy", .{loc}), loc, "v1", target, optimize, c_mod, c_icu_mod, lto_enabled, is_macos);
    }

    // Unit tests
    //
    // Bug #25: the suite previously reused `root_module` and therefore ran
    // under the default ReleaseFast, compiling out safety-checked UB
    // (integer overflow, OOB slice panics) exactly where regression tests
    // must catch it. Give the tests their own Debug-optimized module;
    // shipped libraries keep ReleaseFast.
    const test_root_module = b.createModule(.{
        .root_source_file = b.path("src/fts5_icu.zig"),
        .target = target,
        .optimize = debug_mode,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
            .{ .name = "c_icu", .module = c_icu_mod },
            .{ .name = "build_options", .module = options_mod },
        },
    });
    linkModule(test_root_module, b, is_macos);

    const unit_tests = b.addTest(.{
        .root_module = test_root_module,
    });
    configureArtifact(unit_tests, false);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Bug #42: helper for compiling and registering test runner executables
    const addTestRunner = struct {
        fn apply(
            builder: *std.Build,
            name: []const u8,
            source_file: []const u8,
            step_name: []const u8,
            step_desc: []const u8,
            target_step: std.Build.ResolvedTarget,
            opt: OptimizeMode,
            c_m: *std.Build.Module,
            c_icu_m: *std.Build.Module,
            enable_lto: bool,
            macos: bool,
        ) void {
            const mod = builder.createModule(.{
                .root_source_file = builder.path(source_file),
                .target = target_step,
                .optimize = opt,
                .imports = &.{
                    .{ .name = "c", .module = c_m },
                    .{ .name = "c_icu", .module = c_icu_m },
                },
            });
            linkModule(mod, builder, macos);

            const exe = builder.addExecutable(.{
                .name = name,
                .root_module = mod,
            });
            configureArtifact(exe, enable_lto);

            const run_cmd = builder.addRunArtifact(exe);
            const step = builder.step(step_name, step_desc);
            step.dependOn(&run_cmd.step);
        }
    }.apply;

    // Test executables
    addTestRunner(b, "test_transliterator", "src/test_transliterator.zig", "run-transliterator", "Run ICU transliterator test", target, optimize, c_mod, c_icu_mod, lto_enabled, is_macos);
    addTestRunner(b, "locale_specific_tests", "src/locale_specific_tests.zig", "run-locale-tests", "Run locale-specific transliterator tests", target, optimize, c_mod, c_icu_mod, lto_enabled, is_macos);
    addTestRunner(b, "test_locale_tokenizer", "src/test_locale_tokenizer.zig", "run-tokenizer-test", "Run locale tokenizer test", target, optimize, c_mod, c_icu_mod, lto_enabled, is_macos);
}
