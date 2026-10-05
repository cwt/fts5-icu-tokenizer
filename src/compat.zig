//! Cross-version compatibility shims for Zig 0.16.0 / 0.17.0.
//!
//! Every helper here has an implementation that compiles on BOTH toolchains,
//! so no `@hasField` gating is needed at the call sites.
const std = @import("std");

/// Zig 0.17 removed `Allocator.dupeZ`. Allocate a NUL-terminated copy.
/// `Allocator.allocSentinel` exists in both 0.16 and 0.17.
pub fn dupeZ(allocator: std.mem.Allocator, s: []const u8) std.mem.Allocator.Error![:0]u8 {
    const out = try allocator.allocSentinel(u8, s.len, 0);
    @memcpy(out, s);
    return out;
}
