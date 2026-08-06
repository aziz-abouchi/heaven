const matrix_lib = @import("../../core/matrix.zig");

pub const Rule = struct {
    head: matrix_lib.BobId,
    body: []matrix_lib.BobId,
};
