//! Abstraction sur @import("builtin") — un seul point de vérité pour
//! tester la plateforme. Le reste du code ne devrait plus importer
//! "builtin" directement.
const builtin = @import("builtin");

pub const os   = builtin.os.tag;
pub const arch = builtin.target.cpu.arch;
pub const mode = builtin.mode;

pub const is_windows = builtin.os.tag == .windows;
pub const is_darwin  = builtin.os.tag.isDarwin();
pub const is_linux   = builtin.os.tag == .linux;
pub const is_wasm    = builtin.target.cpu.arch.isWasm();
pub const is_debug   = builtin.mode == .Debug;
pub const is_release = builtin.mode == .ReleaseFast or
                       builtin.mode == .ReleaseSmall;
