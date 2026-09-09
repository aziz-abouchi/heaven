const std = @import("std");
const windows = std.os.windows;

pub const TimeVal = struct {
    sec: i64 = 0,
    usec: i64 = 0,
};

pub const ResourceUsage = struct {
    utime: TimeVal = .{},
    stime: TimeVal = .{},
    maxrss: i64 = 0,
};

extern "kernel32" fn GetProcessTimes(
    hProcess: windows.HANDLE,
    lpCreationTime: *windows.FILETIME,
    lpExitTime: *windows.FILETIME,
    lpKernelTime: *windows.FILETIME,
    lpUserTime: *windows.FILETIME,
) callconv(std.builtin.CallingConvention.winapi) windows.BOOL;

fn filetimeToTimeVal(ft: windows.FILETIME) TimeVal {
    const intervals = (@as(u64, ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
    const total_us = intervals / 10; // 100ns -> 1µs
    return .{
        .sec = @intCast(total_us / 1_000_000),
        .usec = @intCast(total_us % 1_000_000),
    };
}

pub fn getResourceUsage() ResourceUsage {
    var creation: windows.FILETIME = undefined;
    var exit: windows.FILETIME = undefined;
    var kernel: windows.FILETIME = undefined;
    var user: windows.FILETIME = undefined;

    const handle = windows.kernel32.GetCurrentProcess();
    if (GetProcessTimes(handle, &creation, &exit, &kernel, &user) != 0) {
        return .{
            .utime = filetimeToTimeVal(user),
            .stime = filetimeToTimeVal(kernel),
            .maxrss = 0,
        };
    }

    return .{};
}