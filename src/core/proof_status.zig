const std = @import("std");

pub const Status = enum {
    proposed,
    solved,
    axiom,
    canonically_equivalent,
    trusted,
    kernel_certified,
    legacy_unclassified,
};

pub fn isCertified(s: Status) bool {
    return s == .kernel_certified;
}

pub fn statusFromLegacy(v: bool) Status {
    return if (v) .legacy_unclassified else .proposed;
}

pub fn isProved(s: Status) bool {
    return switch (s) {
        .kernel_certified, .axiom, .canonically_equivalent, .trusted => true,
        .proposed, .solved, .legacy_unclassified => false,
    };
}

pub fn displayLabel(s: Status) []const u8 {
    return switch (s) {
        .proposed => "[ ]",
        .solved => "[SOLVED]",
        .axiom => "[AXIOM]",
        .canonically_equivalent => "[EQ]",
        .trusted => "[TRUSTED]",
        .kernel_certified => "[PROVED]",
        .legacy_unclassified => "[LEGACY]",
    };
}

test "isCertified only for kernel_certified" {
    try std.testing.expect(isCertified(.kernel_certified));
    try std.testing.expect(!isCertified(.proposed));
    try std.testing.expect(!isCertified(.solved));
    try std.testing.expect(!isCertified(.axiom));
    try std.testing.expect(!isCertified(.canonically_equivalent));
    try std.testing.expect(!isCertified(.trusted));
    try std.testing.expect(!isCertified(.legacy_unclassified));
}

test "statusFromLegacy true -> legacy_unclassified" {
    try std.testing.expectEqual(Status.legacy_unclassified, statusFromLegacy(true));
}

test "statusFromLegacy false -> proposed" {
    try std.testing.expectEqual(Status.proposed, statusFromLegacy(false));
}

test "displayLabel kernel -> PROVED" {
    try std.testing.expectEqualStrings("[PROVED]", displayLabel(.kernel_certified));
}

test "displayLabel legacy -> LEGACY not PROVED" {
    try std.testing.expectEqualStrings("[LEGACY]", displayLabel(.legacy_unclassified));
    try std.testing.expect(!std.mem.eql(u8, displayLabel(.legacy_unclassified), "[PROVED]"));
}
