const std = @import("std");
const Allocator = std.mem.Allocator;

/// Module system for Heaven
pub const Module = struct {
    name: []const u8,
    exports: std.StringHashMap(bool),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) Module {
        return .{
            .name = name,
            .exports = std.StringHashMap(bool).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Module) void {
        self.exports.deinit();
    }

    pub fn export(self: *Module, name: []const u8) !void {
        try self.exports.put(name, true);
    }

    pub fn isExported(self: *Module, name: []const u8) bool {
        return self.exports.get(name) orelse false;
    }
};

pub const ModuleRegistry = struct {
    modules: std.StringHashMap(Module),
    allocator: Allocator,

    pub fn init(allocator: Allocator) ModuleRegistry {
        return .{
            .modules = std.StringHashMap(Module).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ModuleRegistry) void {
        var it = self.modules.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.modules.deinit();
    }

    pub fn register(self: *ModuleRegistry, module: Module) !void {
        try self.modules.put(module.name, module);
    }

    pub fn get(self: *ModuleRegistry, name: []const u8) ?*Module {
        return self.modules.getPtr(name);
    }
};
