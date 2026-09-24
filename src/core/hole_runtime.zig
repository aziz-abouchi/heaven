//! HoleRuntime — gestion runtime des trous (`_`).
//!
//! Extrait de `heaven_expr.zig` (RFC-0001). Le runtime est une pure
//! logique sur `Store` + `HoleState` : pas de dépendance à `Heaven`
//! ni à `Eval`. La mise à jour de `hole_state.last_root_expr` se fait
//! via un pointeur vers `Heaven.last_root_expr`.

const std = @import("std");
const expr = @import("expr");
const types = @import("types");
const hole_mod = @import("hole");

const Store = expr.Store;
const Id = expr.Id;

pub const HoleRuntime = struct {
    store: *Store,
    allocator: std.mem.Allocator,
    hole_state: *hole_mod.HoleState,
    /// Pointeur vers `Heaven.last_root_expr`. Lu quand on crée un trou
    /// pour synchroniser `hole_state.last_root_expr`.
    last_root_expr: *?Id,

    pub fn init(
        store: *Store,
        allocator: std.mem.Allocator,
        hole_state: *hole_mod.HoleState,
        last_root_expr: *?Id,
    ) HoleRuntime {
        return .{
            .store = store,
            .allocator = allocator,
            .hole_state = hole_state,
            .last_root_expr = last_root_expr,
        };
    }

    pub fn fresh(self: *HoleRuntime) !Id {
        const id = try self.hole_state.fresh(self.store);
        self.hole_state.last_root_expr = self.last_root_expr.*;
        return id;
    }

    pub fn refine(self: *HoleRuntime, hole_id: u32, expr_id: Id) !void {
        try self.hole_state.refine(hole_id, expr_id);
    }

    pub fn hasUnresolved(self: *HoleRuntime, id: Id) bool {
        return self.hole_state.hasUnresolved(self.store, id);
    }

    fn findHoleParent(self: *HoleRuntime, root: Id, hole_id: u32) ?Id {
        if (root >= self.store.len()) return null;
        const node = self.store.get(root);
        if (node.tag == .hole and node.payload == hole_id) return root;
        for (self.store.spanSliceConst(node.span_a)) |c| {
            if (self.findHoleParent(c, hole_id)) |p| return p;
        }
        for (self.store.spanSliceConst(node.span_b)) |c| {
            if (self.findHoleParent(c, hole_id)) |p| return p;
        }
        return null;
    }

    fn findParentOf(self: *HoleRuntime, root: Id, target: Id) ?Id {
        if (root >= self.store.len()) return null;
        const node = self.store.get(root);
        const ca = self.store.spanSliceConst(node.span_a);
        const cb = self.store.spanSliceConst(node.span_b);
        for (ca) |c| if (c == target) return root;
        for (cb) |c| if (c == target) return root;
        for (ca) |c| if (self.findParentOf(c, target)) |p| return p;
        for (cb) |c| if (self.findParentOf(c, target)) |p| return p;
        return null;
    }

    fn inferHoleType(self: *HoleRuntime, hole_id: u32) !?Id {
        const root = self.hole_state.last_root_expr orelse return null;
        const hole_node = self.findHoleParent(root, hole_id) orelse return null;
        const parent = self.findParentOf(root, hole_node) orelse return null;
        const pnode = self.store.get(parent);

        if (pnode.tag == .apply) {
            const fnode = self.store.get(pnode.payload);
            if (fnode.tag == .sym) {
                const op = self.store.interner.resolve(fnode.payload);
                if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-") or
                    std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "/") or
                    std.mem.eql(u8, op, "%") or std.mem.eql(u8, op, "^"))
                {
                    return try self.store.sym("Int");
                }
                if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=") or
                    std.mem.eql(u8, op, "<") or std.mem.eql(u8, op, ">") or
                    std.mem.eql(u8, op, "<=") or std.mem.eql(u8, op, ">="))
                {
                    return try self.store.sym("Bool");
                }
            }
        }
        return null;
    }

    fn typeStrForId(self: *HoleRuntime, ty: Id) ![]u8 {
        var inf = types.Infer.init(self.store, self.allocator);
        defer inf.deinit();
        return inf.typeStr(&inf.subst, ty, self.allocator);
    }

    pub fn describeHole(self: *HoleRuntime, hole_id: u32) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);

        if (!self.hole_state.holes.contains(hole_id)) {
            try w.print("?{d} (unknown hole)\n", .{hole_id});
            return buf.toOwnedSlice(self.allocator);
        }

        if (try self.inferHoleType(hole_id)) |ty| {
            const ty_str = self.typeStrForId(ty) catch "?";
            defer if (ty_str.ptr != "?".ptr) self.allocator.free(ty_str);
            try w.print("?{d} : {s}\n", .{ hole_id, ty_str });
        } else {
            try w.print("?{d} : ?\n", .{hole_id});
        }

        if (self.hole_state.resolve(hole_id)) |resolved| {
            const r_str = expr.toStringInfix(self.store, resolved, self.allocator) catch "<expr>";
            defer if (r_str.ptr != "<expr>".ptr) self.allocator.free(r_str);
            try w.print("  refined to: {s}\n", .{r_str});
        } else {
            try w.writeAll("  not refined\n");
        }

        return buf.toOwnedSlice(self.allocator);
    }

    pub fn describeAllHoles(self: *HoleRuntime) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);

        if (self.hole_state.holes.count() == 0) {
            try w.writeAll("(no holes)\n");
            return buf.toOwnedSlice(self.allocator);
        }

        const ids = try self.hole_state.listIds(self.allocator);
        defer self.allocator.free(ids);

        for (ids) |id| {
            const desc = try self.describeHole(id);
            defer self.allocator.free(desc);
            try w.writeAll(desc);
        }
        return buf.toOwnedSlice(self.allocator);
    }};
