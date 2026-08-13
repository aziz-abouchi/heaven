const std = @import("std");
const matrix_lib = @import("../core/matrix.zig");

pub const Reasoner = struct {
    pub fn process(matrix: *matrix_lib.Matrix) !bool {
        var overall_changed = false;
        var iterations: usize = 0;

        while (iterations < 20) : (iterations += 1) {
            var local_changed = false;
            var it = matrix.nodes.iterator();

            while (it.next()) |entry| {
                const node_id = entry.key_ptr.*;
                const data = entry.value_ptr.*;

                if (data == .Edge) {
                    const label = data.Edge.label;
                    if (std.mem.eql(u8, label, "PLUS")) {
                        local_changed = try reduceAddition(matrix, node_id, data.Edge) or local_changed;
                    } else if (std.mem.eql(u8, label, "IS")) {
                        local_changed = try propagateProperties(matrix, node_id, data.Edge) or local_changed;
                    }
                }
            }
            if (!local_changed) break;
            overall_changed = true;
        }
        return overall_changed;
    }

    fn reduceAddition(matrix: *matrix_lib.Matrix, edge_id: u32, edge: anytype) !bool {
        const source_root = matrix.findCanonicalInternal(edge_id);
        const target_root = matrix.findCanonicalInternal(edge.target);

        var source_val: ?f64 = null;
        var source_node_id: ?u32 = null;
        var it = matrix.nodes.iterator();
        while (it.next()) |e| {
            const val = e.value_ptr.*;
            if (val == .Scalar and matrix.findCanonicalInternal(e.key_ptr.*) == source_root) {
                source_val = val.Scalar;
                source_node_id = e.key_ptr.*;
                break;
            }
        }

        const target_node = matrix.nodes.get(target_root) orelse return false;
        if (source_val != null and target_node == .Scalar) {
            const res = source_val.? + target_node.Scalar;
            try matrix.updateNode(source_node_id.?, .{ .Scalar = res });
            const done_label = try matrix.allocator.dupe(u8, "DONE");
            try matrix.updateNode(edge_id, .{ .Edge = .{ .target = edge.target, .label = done_label, .weight = 1.0 } });
            // platform.debug.print("[REASONER] Réduction: {d:.2} + {d:.2} -> {d:.2}\n", .{ source_val.?, target_node.Scalar, res });
            return true;
        }
        return false;
    }

    fn propagateProperties(matrix: *matrix_lib.Matrix, edge_id: u32, edge: anytype) !bool {
        const sub_root = matrix.findCanonicalInternal(edge_id);
        const super_root = matrix.findCanonicalInternal(edge.target);
        var changed = false;

        var it = matrix.nodes.iterator();
        while (it.next()) |entry| {
            const p_id = entry.key_ptr.*;
            const p_data = entry.value_ptr.*;

            if (p_data == .Edge and
                matrix.findCanonicalInternal(p_id) == super_root and
                !std.mem.eql(u8, p_data.Edge.label, "IS") and
                !std.mem.eql(u8, p_data.Edge.label, "DONE"))
            {
                if (!hasProperty(matrix, sub_root, p_data.Edge.label)) {
                    try matrix.addEdge(sub_root, p_data.Edge.target, p_data.Edge.label);
                    // platform.debug.print("[REASONER] Héritage: Nœud {d} hérite de '{s}'\n", .{ sub_root, p_data.Edge.label });
                    changed = true;
                }
            }
        }
        return changed;
    }

    fn hasProperty(matrix: *matrix_lib.Matrix, root: u32, label: []const u8) bool {
        var it = matrix.nodes.iterator();
        while (it.next()) |entry| {
            const data = entry.value_ptr.*;
            if (data == .Edge and
                matrix.findCanonicalInternal(entry.key_ptr.*) == root and
                std.mem.eql(u8, data.Edge.label, label)) return true;
        }
        return false;
    }
};
