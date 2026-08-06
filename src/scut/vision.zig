const std = @import("std");
pub const matrix_lib = @import("./core/matrix.zig");
const wasm_impl = @import("vessel/wasm.zig");

export fn pulse_from_browser(hole_id: u32) bool {
    return wasm_impl.pulse_from_browser(hole_id);
}

export fn get_matrix_ptr(matrix_ptr: *matrix_lib.Matrix) *matrix_lib.Matrix {
    return wasm_impl.get_matrix_ptr(matrix_ptr);
}

export fn count_nodes(matrix_ptr: *matrix_lib.Matrix) usize {
    return wasm_impl.count_nodes(matrix_ptr);
}

export fn get_node_type(matrix_ptr: *matrix_lib.Matrix, node_id: u32) u8 {
    return wasm_impl.get_node_type(matrix_ptr, node_id);
}

export fn get_version() u32 {
    return wasm_impl.get_version();
}
