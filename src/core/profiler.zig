pub const ResourceMetrics = struct {
    // Énergie (via RAPL sur Linux, IOKit sur macOS)
    energy_joules: f64 = 0,
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
    cpu_usage_percent: f64 = 0,
};
