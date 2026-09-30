//! Serialisation binaire des Profile (docs/spec/_metrics.md §Sérialisation).
//!
//! Format V1 : compact, stable, content-addressed.
//!
//! Layout :
//!   magic    : 4 octets = "HVP1"
//!   parent   : u8 (0 = null, 1 = present) + u64 (si present)
//!   scope    : u8 (0=local, 1=remote, 2=nested)
//!   field 1  : u8 (tag precision : 0=unavail, 1=measured, 2=estimated)
//!   field 1  : u64 ou f64 (si present)
//!   ... 7 champs dans l'ordre WallTime, CpuTime, Rss, PeakRss, Energy,
//!       Instructions, Allocations
//!
//! L'id n'est PAS serialise : il est recalcule par computeId() a la
//! lecture. Deux profils avec les memes champs ont les memes bytes
//! et le meme id.

const std = @import("std");
const profile_mod = @import("profile.zig");

pub const Profile = profile_mod.Profile;
pub const ProfileId = profile_mod.ProfileId;
pub const ScopeKind = profile_mod.ScopeKind;

pub const MAGIC: [4]u8 = .{ 'H', 'V', 'P', '1' };

pub const DecodeError = error{
    BadMagic,
    BadTag,
    BadScope,
    UnexpectedEof,
    InvalidData,
};

/// Ecrit un Profile dans `writer`. Les bytes sont deterministes :
/// deux profils identiques produisent la meme sequence.
pub fn serialize(p: Profile, writer: anytype) !void {
    try writer.writeAll(&MAGIC);

    // parent
    if (p.parent) |id| {
        try writer.writeByte(1);
        try writer.writeInt(u64, id, .little);
    } else {
        try writer.writeByte(0);
    }

    // scope
    try writer.writeByte(@intFromEnum(p.scope));

    // 7 champs dans l'ordre
    try writeMetricU64(writer, p.wall_time);
    try writeMetricU64(writer, p.cpu_time);
    try writeMetricU64(writer, p.rss);
    try writeMetricU64(writer, p.peak_rss);
    try writeMetricF64(writer, p.energy);
    try writeMetricU64(writer, p.instructions);
    try writeMetricU64(writer, p.allocations);
}

fn writeMetricU64(writer: anytype, m: profile_mod.Metric(u64)) !void {
    switch (m) {
        .measured => |v| {
            try writer.writeByte(1);
            try writer.writeInt(u64, v, .little);
        },
        .estimated => |v| {
            try writer.writeByte(2);
            try writer.writeInt(u64, v, .little);
        },
        .unavailable => try writer.writeByte(0),
    }
}

fn writeMetricF64(writer: anytype, m: profile_mod.Metric(f64)) !void {
    switch (m) {
        .measured => |v| {
            try writer.writeByte(1);
            try writer.writeInt(u64, @bitCast(v), .little);
        },
        .estimated => |v| {
            try writer.writeByte(2);
            try writer.writeInt(u64, @bitCast(v), .little);
        },
        .unavailable => try writer.writeByte(0),
    }
}

/// Lit un Profile depuis `reader`. L'id n'est pas lu : il est
/// recalcule par computeId() en fin de lecture.
pub fn deserialize(reader: anytype) !Profile {
    var magic: [4]u8 = undefined;
    reader.readNoEof(&magic) catch return DecodeError.UnexpectedEof;
    if (!std.mem.eql(u8, &magic, &MAGIC)) return DecodeError.BadMagic;

    var p = Profile.empty();

    // parent
    const has_parent = reader.readByte() catch return DecodeError.UnexpectedEof;
    if (has_parent == 1) {
        p.parent = reader.readInt(u64, .little) catch return DecodeError.UnexpectedEof;
    } else if (has_parent != 0) {
        return DecodeError.InvalidData;
    }

    // scope
    const scope_tag = reader.readByte() catch return DecodeError.UnexpectedEof;
    p.scope = switch (scope_tag) {
        0 => .local,
        1 => .remote,
        2 => .nested,
        else => return DecodeError.BadScope,
    };

    // champs
    p.wall_time = try readMetricU64(reader);
    p.cpu_time = try readMetricU64(reader);
    p.rss = try readMetricU64(reader);
    p.peak_rss = try readMetricU64(reader);
    p.energy = try readMetricF64(reader);
    p.instructions = try readMetricU64(reader);
    p.allocations = try readMetricU64(reader);

    // id recalcule
    _ = p.computeId();
    return p;
}

fn readMetricU64(reader: anytype) !profile_mod.Metric(u64) {
    const tag = reader.readByte() catch return DecodeError.UnexpectedEof;
    return switch (tag) {
        0 => .unavailable,
        1 => .{ .measured = reader.readInt(u64, .little) catch return DecodeError.UnexpectedEof },
        2 => .{ .estimated = reader.readInt(u64, .little) catch return DecodeError.UnexpectedEof },
        else => DecodeError.BadTag,
    };
}

fn readMetricF64(reader: anytype) !profile_mod.Metric(f64) {
    const tag = reader.readByte() catch return DecodeError.UnexpectedEof;
    return switch (tag) {
        0 => .unavailable,
        1 => .{ .measured = @bitCast(reader.readInt(u64, .little) catch return DecodeError.UnexpectedEof) },
        2 => .{ .estimated = @bitCast(reader.readInt(u64, .little) catch return DecodeError.UnexpectedEof) },
        else => DecodeError.BadTag,
    };
}

// ─────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────

const testing = std.testing;

fn roundtrip(p: Profile) !Profile {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try serialize(p, fbs.writer());
    var fbs2 = std.io.fixedBufferStream(fbs.getWritten());
    return deserialize(fbs2.reader());
}

test "profile_ser : round-trip profil vide" {
    var p = Profile.empty();
    _ = p.computeId();
    const p2 = try roundtrip(p);
    try testing.expectEqual(p.id, p2.id);
    try testing.expectEqual(p.parent, p2.parent);
    try testing.expectEqual(p.scope, p2.scope);
    try testing.expectEqual(@as(u8, 0), p2.availableCount());
}

test "profile_ser : round-trip profil rempli" {
    var p = Profile.empty();
    p.wall_time = .{ .measured = 1234567 };
    p.cpu_time = .{ .measured = 890000 };
    p.rss = .{ .measured = 4096 };
    p.peak_rss = .{ .estimated = 8192 };
    p.energy = .{ .measured = 42.5 };
    p.instructions = .{ .measured = 1000000 };
    p.allocations = .{ .estimated = 500 };
    _ = p.computeId();

    const p2 = try roundtrip(p);
    try testing.expectEqual(p.id, p2.id);
    try testing.expectEqual(@as(u64, 1234567), p2.wall_time.valueOrNull().?);
    try testing.expectEqual(@as(f64, 42.5), p2.energy.valueOrNull().?);
    try testing.expectEqual(precision_mod.Precision.estimated, p2.peak_rss.precision());
    try testing.expectEqual(@as(u8, 7), p2.availableCount());
}

test "profile_ser : precision preservee" {
    var p = Profile.empty();
    p.rss = .{ .measured = 4096 };
    p.peak_rss = .{ .estimated = 8192 };
    _ = p.computeId();

    const p2 = try roundtrip(p);
    try testing.expectEqual(precision_mod.Precision.measured, p2.rss.precision());
    try testing.expectEqual(precision_mod.Precision.estimated, p2.peak_rss.precision());
}

test "profile_ser : parent et scope preserves" {
    var p = Profile.empty();
    p.parent = 0xDEADBEEFCAFEBABE;
    p.scope = .nested;
    _ = p.computeId();

    const p2 = try roundtrip(p);
    try testing.expectEqual(@as(?u64, 0xDEADBEEFCAFEBABE), p2.parent);
    try testing.expectEqual(ScopeKind.nested, p2.scope);
    try testing.expectEqual(p.id, p2.id);
}

test "profile_ser : deterministe (memes champs -> memes bytes)" {
    var p1 = Profile.empty();
    p1.wall_time = .{ .measured = 1000 };
    p1.energy = .{ .measured = 42.5 };

    var p2 = Profile.empty();
    p2.wall_time = .{ .measured = 1000 };
    p2.energy = .{ .measured = 42.5 };

    var buf1: [256]u8 = undefined;
    var buf2: [256]u8 = undefined;
    var fbs1 = std.io.fixedBufferStream(&buf1);
    var fbs2 = std.io.fixedBufferStream(&buf2);
    try serialize(p1, fbs1.writer());
    try serialize(p2, fbs2.writer());

    try testing.expectEqualSlices(u8, fbs1.getWritten(), fbs2.getWritten());
}

test "profile_ser : magic invalide -> BadMagic" {
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..4], "XXXX");
    var fbs = std.io.fixedBufferStream(buf[0..4]);
    try testing.expectError(DecodeError.BadMagic, deserialize(fbs.reader()));
}

test "profile_ser : tag invalide -> BadTag" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try serialize(Profile.empty(), fbs.writer());
    const written = fbs.getWritten();
    // Corrompre le tag du premier champ (offset = 4 magic + 1 parent + 1 scope = 6)
    written[6] = 99;
    var fbs2 = std.io.fixedBufferStream(written);
    try testing.expectError(DecodeError.BadTag, deserialize(fbs2.reader()));
}

test "profile_ser : scope invalide -> BadScope" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try serialize(Profile.empty(), fbs.writer());
    const written = fbs.getWritten();
    // Corrompre le scope (offset = 4 magic + 1 parent = 5)
    written[5] = 99;
    var fbs2 = std.io.fixedBufferStream(written);
    try testing.expectError(DecodeError.BadScope, deserialize(fbs2.reader()));
}

// Import pour les tests (Precision)
const precision_mod = @import("precision.zig");
