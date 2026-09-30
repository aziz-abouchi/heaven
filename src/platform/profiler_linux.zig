const std = @import("std");
const c = @cImport({
    @cInclude("sys/resource.h");
    @cInclude("linux/perf_event.h");
    @cInclude("fcntl.h");
});

pub const TimeVal = struct { sec: i64, usec: i64 };

pub const ResourceUsage = struct {
    utime: TimeVal,
    stime: TimeVal,
    maxrss: usize,
    max_rss_bytes: usize,
};

pub fn getResourceUsage() ResourceUsage {
    const usage = std.posix.getrusage(std.posix.rusage.SELF);
    const rss_kb = @as(usize, @intCast(usage.maxrss));

    return ResourceUsage{
        .utime = .{ .sec = usage.utime.sec, .usec = usage.utime.usec },
        .stime = .{ .sec = usage.stime.sec, .usec = usage.stime.usec },
        // Sur Linux, maxrss est en kilo-octets → convertir en octets
        .maxrss = rss_kb,                 // Linux : en Ko
        .max_rss_bytes = rss_kb * 1024,   // conversion en octets
    };
}

pub fn measureEnergy() !f64 {
    // Lecture via RAPL (Intel) ou AMD Energy
    const file = try std.fs.openFileAbsolute(
        "/sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj", 
        .{}
    );
    defer file.close();
    var buf: [32]u8 = undefined;
    const len = try file.read(&buf);
    const energy_uj = try std.fmt.parseInt(u64, std.mem.trim(u8, buf[0..len], "\n"), 10);
    return @as(f64, @floatFromInt(energy_uj)) / 1_000_000.0; // Convertir en Joules
}

pub fn measureMemory() !u64 {
    var rusage: c.rusage = undefined;
    _ = c.getrusage(c.RUSAGE_SELF, &rusage);
    return @intCast(rusage.ru_maxrss); // KB sur Linux
}

pub fn measureCPU() !u64 {
    // Via perf_event_open pour les cycles CPU
    var perf_attr: std.os.linux.perf_event_attr = .{};
    const fd = std.os.linux.syscall2(
        .perf_event_open,
        @intFromPtr(&perf_attr),
        0, // pid = self
    );
    _ = fd;
    // ... lecture des cycles
}

// ─────────────────────────────────────────────────────────────
// Extension : mesure d'un process enfant (bench)
// ─────────────────────────────────────────────────────────────

/// Usage de tous les processus enfants termines (RUSAGE_CHILDREN).
/// Les champs sont cumulatifs : l'appelant doit faire un delta
/// avant/apres chaque spawn pour mesurer un enfant specifique.
pub fn getChildrenUsage() ResourceUsage {
    const usage = std.posix.getrusage(std.posix.rusage.CHILDREN);
    const rss_kb = @as(usize, @intCast(usage.maxrss));
    return ResourceUsage{
        .utime = .{ .sec = usage.utime.sec, .usec = usage.utime.usec },
        .stime = .{ .sec = usage.stime.sec, .usec = usage.stime.usec },
        .maxrss = rss_kb,
        .max_rss_bytes = rss_kb * 1024,
    };
}

/// Energie CPU totale (Intel RAPL). Retourne null si non
/// disponible (AMD sans module, VM, conteneur sans /sys).
pub fn readEnergyUj() ?u64 {
    const f = std.fs.openFileAbsolute(
        "/sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj",
        .{},
    ) catch return null;
    defer f.close();
    var buf: [32]u8 = undefined;
    const n = f.read(&buf) catch return null;
    return std.fmt.parseInt(u64, std.mem.trim(u8, buf[0..n], "\n \t"), 10) catch null;
}

/// Temperature d'une zone thermique, en millidegres Celsius.
/// Retourne null si la zone n'existe pas.
pub fn readTempMc(zone: u8) ?i64 {
    var path_buf: [64]u8 = undefined;
    const path = std.fmt.bufPrint(
        &path_buf,
        "/sys/class/thermal/thermal_zone{d}/temp",
        .{zone},
    ) catch return null;
    const f = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer f.close();
    var buf: [32]u8 = undefined;
    const n = f.read(&buf) catch return null;
    return std.fmt.parseInt(i64, std.mem.trim(u8, buf[0..n], "\n \t"), 10) catch null;
}
