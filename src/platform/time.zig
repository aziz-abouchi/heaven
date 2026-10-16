// HEAVEN:time — extraction time (refactor plateforme)
const std = @import("std");

pub const ns_per_s = std.time.ns_per_s;
pub const ns_per_us = std.time.ns_per_us;

pub fn milliTimestamp() i64 {
    return std.time.milliTimestamp();
}

pub fn nanoTimestamp() i128 {
    return std.time.nanoTimestamp();
}

pub fn sleep(ns: u64) void {
    std.time.sleep(ns);
}
