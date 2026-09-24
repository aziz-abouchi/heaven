pub const target_os = @tagName(builtin.os.tag);
pub const target_arch = @tagName(builtin.cpu.arch);

pub const Intrinsics = @import("intrinsics.zig").Intrinsics;
