const std = @import("std");
const c = @cImport({
    @cInclude("sys/resource.h");
    @cInclude("linux/perf_event.h");
    @cInclude("fcntl.h");
});

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
    const fd = std.os.linux.syscall2(
        .perf_event_open,
        @intFromPtr(&perf_attr),
        0, // pid = self
    );
    // ... lecture des cycles
}
