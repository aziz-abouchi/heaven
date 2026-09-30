const std = @import("std");
const os = std.os;

pub const TimeVal = struct {
    sec: i64,
    usec: i64,
};

pub const ResourceUsage = struct {
    utime: TimeVal,
    stime: TimeVal,
    maxrss: usize,
    max_rss_bytes: usize,
};

pub fn getResourceUsage() ResourceUsage {
    const usage = std.posix.getrusage(std.posix.rusage.SELF);
    const rss = @as(usize, @intCast(usage.maxrss));

    return ResourceUsage{
        .utime = .{ .sec = usage.utime.sec, .usec = usage.utime.usec },
        .stime = .{ .sec = usage.stime.sec, .usec = usage.stime.usec },
        .maxrss = rss,
        .max_rss_bytes = rss,   // sur macOS, maxrss est déjà en octets

    };
}

pub fn getMemoryUsage() u64 {
    var info: os.darwin.mach_task_basic_info = undefined;
    var count: os.darwin.mach_msg_type_number_t = os.darwin.MACH_TASK_BASIC_INFO_COUNT;

    const kret = os.darwin.task_info(
        os.darwin.mach_task_self(),
        os.darwin.MACH_TASK_BASIC_INFO,
        @ptrCast(&info),
        &count,
    );

    if (kret == 0) {
        return info.resident_size; // Taille en octets
    }
    return 0;
}

pub fn readEnergyUJ() u64 {
    // RAPL sysfs n'est pas accessible directement sur macOS.
    // Retourner 0 ou stupper la mesure d'énergie sur Darwin.
    return 0;
}

// ─────────────────────────────────────────────────────────────
// Extension : mesure d'un process enfant (bench)
// ─────────────────────────────────────────────────────────────

/// RUSAGE_CHILDREN marche sur Darwin comme sur Linux.
pub fn getChildrenUsage() ResourceUsage {
    const usage = std.posix.getrusage(std.posix.rusage.CHILDREN);
    const rss = @as(usize, @intCast(usage.maxrss));
    return ResourceUsage{
        .utime = .{ .sec = usage.utime.sec, .usec = usage.utime.usec },
        .stime = .{ .sec = usage.stime.sec, .usec = usage.stime.usec },
        .maxrss = rss,
        .max_rss_bytes = rss, // macOS : deja en octets
    };
}

/// Pas de RAPL sur macOS. Necessiterait `powermetrics` (root).
/// Stub a remplacer par IOKit / SMC si besoin.
pub fn readEnergyUj() ?u64 {
    return null;
}

/// Temperature : necessite IOKit / SMC. Stub.
pub fn readTempMc(_: u8) ?i64 {
    return null;
}
