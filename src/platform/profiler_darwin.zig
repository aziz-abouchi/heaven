const std = @import("std");
const os = std.os;

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
