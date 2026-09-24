const std = @import("std");

test {
    _ = @import("backend/test_wasm.zig");
    _ = @import("kernel/test_transform.zig");
    _ = @import("tests/test_e2e_wasm.zig");
    _ = @import("tests/test_full_pipeline.zig");
}
