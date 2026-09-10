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
