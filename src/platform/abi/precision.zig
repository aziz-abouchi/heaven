//! Types de précision pour la couche platform (docs/spec/_platform.md P3).
//!
//! Une mesure quantitative porte sa précision dans son type :
//!   - Precision  : mesure / estimation / indisponible
//!   - Monotonic  : rigoureux / standard / indisponible
//!
//! Le marqueur de Precision peut être un paramètre de type (via `Value`)
//! ou une variante runtime (via `Metric`). Le compilateur peut refuser
//! l'usage d'une `Value(T, .estimated)` là où `Value(T, .measured)` est
//! requis.

const std = @import("std");

/// Précision d'une mesure quantitative.
pub const Precision = enum {
    measured,
    estimated,
    unavailable,

    pub fn isAvailable(self: Precision) bool {
        return self != .unavailable;
    }

    /// Combinaison : le minimum des deux précisions (le moins fiable
    /// l'emporte). Utilisé quand une valeur dérive de plusieurs sources.
    pub fn combine(a: Precision, b: Precision) Precision {
        if (a == .unavailable or b == .unavailable) return .unavailable;
        if (a == .estimated or b == .estimated) return .estimated;
        return .measured;
    }
};

/// Nature d'une horloge monotone.
pub const Monotonic = enum {
    rigorous,    // insulated, monotone, garanti
    standard,    // monotone, peut subir NTP / freq scaling
    unavailable,

    pub fn isAvailable(self: Monotonic) bool {
        return self != .unavailable;
    }

    pub fn combine(a: Monotonic, b: Monotonic) Monotonic {
        if (a == .unavailable or b == .unavailable) return .unavailable;
        if (a == .standard or b == .standard) return .standard;
        return .rigorous;
    }
};

/// Valeur mesurée, typée par sa précision. `P` est un paramètre de
/// compilation : `Value(u64, .measured)` et `Value(u64, .estimated)`
/// sont deux types distincts.
pub fn Value(comptime T: type, comptime P: Precision) type {
    return struct {
        value: T,

        pub const precision: Precision = P;

        const Self = @This();

        pub fn init(v: T) Self {
            return .{ .value = v };
        }

        pub fn as(self: Self) T {
            return self.value;
        }
    };
}

/// Mesure disponible ou non. Contrairement à `Value`, l'indisponibilité
/// est une variante runtime, pas un paramètre de type.
pub fn Metric(comptime T: type) type {
    return union(enum) {
        measured: T,
        estimated: T,
        unavailable,

        const Self = @This();

        pub fn precision(self: Self) Precision {
            return switch (self) {
                .measured => .measured,
                .estimated => .estimated,
                .unavailable => .unavailable,
            };
        }

        pub fn isAvailable(self: Self) bool {
            return self != .unavailable;
        }

        /// Retourne la valeur si disponible, sinon null.
        pub fn valueOrNull(self: Self) ?T {
            return switch (self) {
                .measured => |v| v,
                .estimated => |v| v,
                .unavailable => null,
            };
        }
    };
}

// ─────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────

test "Precision : isAvailable" {
    try std.testing.expect(Precision.measured.isAvailable());
    try std.testing.expect(Precision.estimated.isAvailable());
    try std.testing.expect(!Precision.unavailable.isAvailable());
}

test "Precision : combine prend le minimum" {
    const m = Precision.measured;
    const e = Precision.estimated;
    const u = Precision.unavailable;

    try std.testing.expectEqual(m, Precision.combine(m, m));
    try std.testing.expectEqual(e, Precision.combine(m, e));
    try std.testing.expectEqual(e, Precision.combine(e, m));
    try std.testing.expectEqual(e, Precision.combine(e, e));
    try std.testing.expectEqual(u, Precision.combine(m, u));
    try std.testing.expectEqual(u, Precision.combine(e, u));
    try std.testing.expectEqual(u, Precision.combine(u, m));
}

test "Monotonic : combine prend le minimum" {
    const r = Monotonic.rigorous;
    const s = Monotonic.standard;
    const u = Monotonic.unavailable;

    try std.testing.expectEqual(r, Monotonic.combine(r, r));
    try std.testing.expectEqual(s, Monotonic.combine(r, s));
    try std.testing.expectEqual(s, Monotonic.combine(s, s));
    try std.testing.expectEqual(u, Monotonic.combine(r, u));
}

test "Value : precision est un parametre de type" {
    const V = Value(u64, .measured);
    const v = V.init(42);
    try std.testing.expectEqual(@as(u64, 42), v.as());
    try std.testing.expectEqual(Precision.measured, V.precision);
}

test "Value : deux precisions differentes sont des types distincts" {
    const A = Value(u64, .measured);
    const B = Value(u64, .estimated);
    try std.testing.expect(A != B);
}

test "Metric : isAvailable et precision" {
    const m = Metric(u64){ .measured = 42 };
    const e = Metric(u64){ .estimated = 40 };
    const u = Metric(u64){ .unavailable = {} };

    try std.testing.expect(m.isAvailable());
    try std.testing.expect(e.isAvailable());
    try std.testing.expect(!u.isAvailable());

    try std.testing.expectEqual(Precision.measured, m.precision());
    try std.testing.expectEqual(Precision.estimated, e.precision());
    try std.testing.expectEqual(Precision.unavailable, u.precision());
}

test "Metric : valueOrNull retourne null si indisponible" {
    const m = Metric(u64){ .measured = 42 };
    const u = Metric(u64){ .unavailable = {} };

    try std.testing.expectEqual(@as(?u64, 42), m.valueOrNull());
    try std.testing.expectEqual(@as(?u64, null), u.valueOrNull());
}
