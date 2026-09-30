//! Erreur unifiee de la couche platform (docs/spec/_platform.md P5).
//!
//! Toute operation exterieure retourne Result<T, PlatformError>.
//! Trois variantes strictement distinguees :
//!   - unavailable : la plateforme ne fournit pas l'operation
//!   - denied      : capability insuffisante
//!   - failed(why) : l'operation a echoue pour une raison locale

const std = @import("std");

/// Raison d'echec locale. Codes stables, pas de chaine libre.
pub const FailureReason = enum {
    not_found,
    already_exists,
    permission,
    io,
    connection_refused,
    timeout,
    out_of_memory,
    out_of_range,
    invalid_argument,
    busy,
    interrupted,
    other,
};

pub const PlatformError = union(enum) {
    unavailable,
    denied,
    failed: FailureReason,

    const Self = @This();

    pub const unavail: Self = .unavailable;
    pub const deny: Self = .denied;

    /// Erreur fatale ? `denied` est un bug de conception, `unavailable`
    /// et `failed` sont recuperables.
    pub fn isFatal(self: Self) bool {
        return self == .denied;
    }

    /// L'operation peut-elle etre retentee telle quelle ?
    pub fn isRetryable(self: Self) bool {
        return switch (self) {
            .unavailable => true,
            .denied => false,
            .failed => |why| switch (why) {
                .busy, .timeout, .interrupted => true,
                else => false,
            },
        };
    }

    pub fn fmt(self: Self, writer: anytype) !void {
        switch (self) {
            .unavailable => try writer.writeAll("unavailable"),
            .denied => try writer.writeAll("denied"),
            .failed => |why| try writer.print("failed({s})", .{@tagName(why)}),
        }
    }
};

/// Alias pour les signatures : Result<T, PlatformError>.
pub fn Result(comptime T: type) type {
    return std.meta.Tuple(&.{ ?T, ?PlatformError });
}

// ─────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────

test "PlatformError : variantes distinctes" {
    const u: PlatformError = .unavailable;
    const d: PlatformError = .denied;
    const f: PlatformError = .{ .failed = .not_found };

    try std.testing.expect(std.meta.eql(u, PlatformError.unavail));
    try std.testing.expect(std.meta.eql(d, PlatformError.deny));
    try std.testing.expect(std.meta.eql(f, PlatformError{ .failed = .not_found }));
}

test "PlatformError : isFatal seulement denied" {
    try std.testing.expect(!PlatformError.unavail.isFatal());
    try std.testing.expect(PlatformError.deny.isFatal());
    try std.testing.expect(!(PlatformError{ .failed = .not_found }).isFatal());
}

test "PlatformError : isRetryable par variante" {
    try std.testing.expect(PlatformError.unavail.isRetryable());
    try std.testing.expect(!PlatformError.deny.isRetryable());
    try std.testing.expect((PlatformError{ .failed = .busy }).isRetryable());
    try std.testing.expect((PlatformError{ .failed = .timeout }).isRetryable());
    try std.testing.expect((PlatformError{ .failed = .interrupted }).isRetryable());
    try std.testing.expect(!(PlatformError{ .failed = .not_found }).isRetryable());
    try std.testing.expect(!(PlatformError{ .failed = .permission }).isRetryable());
}

test "PlatformError : fmt" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();

    try PlatformError.unavail.fmt(w);
    try std.testing.expectEqualStrings("unavailable", fbs.getWritten());

    fbs.reset();
    try PlatformError.deny.fmt(w);
    try std.testing.expectEqualStrings("denied", fbs.getWritten());

    fbs.reset();
    try (PlatformError{ .failed = .timeout }).fmt(w);
    try std.testing.expectEqualStrings("failed(timeout)", fbs.getWritten());
}
