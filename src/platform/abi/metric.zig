//! Metriques typées par precision (docs/spec/_metrics.md).
//!
//! Contrairement a `precision.Metric(T)` (variante runtime), ce
//! module expose `Metric(K, P)` ou K est un marqueur de kind et P
//! est un parametre de compilation. Le compilateur peut refuser un
//! usage qui exige `measured` sur une source `estimated`.
//!
//! Les Kinds ci-dessous sont des marqueurs de type, pas des valeurs.
//! Ils servent a typer les metriques d'un Profile.

const std = @import("std");
const precision_mod = @import("precision.zig");

pub const Precision = precision_mod.Precision;

// ─────────────────────────────────────────────────────────────
// Kinds de metrique
// ─────────────────────────────────────────────────────────────

/// Marqueur : duree d'horloge murale.
pub const WallTime = struct {
    pub const unit = "ns";
};

/// Marqueur : temps CPU (user + sys).
pub const CpuTime = struct {
    pub const unit = "ns";
};

/// Marqueur : memoire residente (RSS).
pub const Rss = struct {
    pub const unit = "bytes";
};

/// Marqueur : pic de memoire.
pub const PeakRss = struct {
    pub const unit = "bytes";
};

/// Marqueur : energie consommee.
pub const Energy = struct {
    pub const unit = "joules";
};

/// Marqueur : instructions executees.
pub const Instructions = struct {
    pub const unit = "count";
};

/// Marqueur : allocations.
pub const Allocations = struct {
    pub const unit = "count";
};

// ─────────────────────────────────────────────────────────────
// Metric(K, P)
// ─────────────────────────────────────────────────────────────

/// Type scalaire associe a un Kind.
/// Energy en f64 (joules fractionnaires), les autres en u64.
pub fn Scalar(comptime K: type) type {
    return if (K == Energy) f64 else u64;
}

/// Metrique typée. P est un parametre de compilation, donc
/// `Metric(WallTime, .measured)` et `Metric(WallTime, .estimated)`
/// sont deux types distincts.
pub fn Metric(comptime K: type, comptime P: Precision) type {
    const T = Scalar(K);
    return struct {
        value: if (P == .unavailable) void else T,

        pub const kind = K;
        pub const precision: Precision = P;
        pub const unit: []const u8 = K.unit;

        const Self = @This();

        pub fn init(v: T) Self {
            if (P == .unavailable) {
                @compileError("Metric(K, .unavailable) n'a pas de valeur");
            }
            return .{ .value = v };
        }

        pub fn unavailable() Self {
            if (P != .unavailable) {
                @compileError("Metric(K, P) avec P != .unavailable n'a pas de constructeur unavailable");
            }
            return .{ .value = {} };
        }

        pub fn as(self: Self) T {
            if (P == .unavailable) {
                @compileError("Metric(K, .unavailable) n'a pas de valeur");
            }
            return self.value;
        }

        pub fn isAvailable(self: Self) bool {
            _ = self;
            return P != .unavailable;
        }
    };
}

// ─────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────

test "Scalar : u64 pour compteurs, f64 pour energy" {
    try std.testing.expectEqual(u64, Scalar(WallTime));
    try std.testing.expectEqual(u64, Scalar(Rss));
    try std.testing.expectEqual(u64, Scalar(Instructions));
    try std.testing.expectEqual(f64, Scalar(Energy));
}

test "Metric : init, as, precision" {
    const M = Metric(WallTime, .measured);
    const m = M.init(1234);
    try std.testing.expectEqual(@as(u64, 1234), m.as());
    try std.testing.expectEqual(Precision.measured, M.precision);
    try std.testing.expect(m.isAvailable());
}

test "Metric : energy en f64" {
    const M = Metric(Energy, .measured);
    const m = M.init(42.5);
    try std.testing.expectEqual(@as(f64, 42.5), m.as());
}

test "Metric : deux precisions sont des types distincts" {
    const A = Metric(WallTime, .measured);
    const B = Metric(WallTime, .estimated);
    try std.testing.expect(A != B);
}

test "Metric : unavailable est un type sans valeur" {
    const M = Metric(Rss, .unavailable);
    const m = M.unavailable();
    try std.testing.expect(!m.isAvailable());
    try std.testing.expectEqual(Precision.unavailable, M.precision);
}

test "Metric : unit provient du Kind" {
    try std.testing.expectEqualStrings("ns", Metric(WallTime, .measured).unit);
    try std.testing.expectEqualStrings("joules", Metric(Energy, .measured).unit);
    try std.testing.expectEqualStrings("bytes", Metric(Rss, .measured).unit);
}
