const std = @import("std");
const platform = @import("platform");

pub const ResourceMetrics = struct {
    // Énergie (via RAPL sur Linux, IOKit sur macOS)
    energy_joules: f64 = 0.0,
    memory_peak_kb: u64 = 0,
    cpu_cycles: u64 = 0,
    cpu_instructions: u64 = 0,

    // Mémoire
    memory_allocations: u64 = 0,
    memory_bytes: u64 = 0,
    memory_peak: u64 = 0,

    // Réseau
    network_bytes_sent: u64 = 0,
    network_bytes_recv: u64 = 0,

    // Temps
    wall_time_ns: u64 = 0,
    cpu_time_ns: u64 = 0,

    // Charge CPU
    cpu_usage_percent: f64 = 0.0,
};

pub const Profiler = struct {
    start_time: i128 = 0,
    start_energy_uj: u64 = 0,

    pub fn start() Profiler {
        return .{
            .start_time = platform.time.nanoTimestamp(),
            .start_energy_uj = platform.readEnergyUJ() catch 0,
        };
    }

    pub fn stop(self: *Profiler) ResourceMetrics {
        const end_time = platform.time.nanoTimestamp();
        const end_energy_uj = platform.readEnergyUJ() catch self.start_energy_uj;

        const elapsed_ns = @as(u64, @intCast(end_time - self.start_time));

        const rusage = platform.posix.getrusage(platform.posix.rusage.SELF);

        // Calcul du temps CPU (User + System) en nanosecondes
        const cpu_time_ns = @as(u64, @intCast(rusage.utime.sec + rusage.stime.sec)) * platform.time.ns_per_s +
            @as(u64, @intCast(rusage.utime.usec + rusage.stime.usec)) * platform.time.ns_per_us;

        const energy_diff_uj = if (end_energy_uj > self.start_energy_uj) end_energy_uj - self.start_energy_uj else 0;

        return .{
            .wall_time_ns = elapsed_ns,
            .cpu_time_ns = cpu_time_ns,
            .energy_joules = @as(f64, @floatFromInt(energy_diff_uj)) / 1_000_000.0,
            .memory_peak_kb = @intCast(rusage.maxrss),
        };
    }
};
