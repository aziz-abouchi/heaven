const std = @import("std");
const matrix_lib = @import("../core/matrix.zig");

pub fn pulse_from_browser(hole_id: u32) bool {
    _ = hole_id;
    return true;
}

pub fn get_matrix_ptr(matrix_ptr: *matrix_lib.Matrix) *matrix_lib.Matrix {
    return matrix_ptr;
}

pub fn count_nodes(matrix_ptr: *matrix_lib.Matrix) usize {
    return matrix_ptr.nodes.count();
}

pub fn get_node_type(matrix_ptr: *matrix_lib.Matrix, node_id: u32) u8 {
    const node = matrix_ptr.nodes.get(node_id) orelse return 0;
    return @intFromEnum(node);
}

pub fn get_version() u32 {
    return 1;
}
