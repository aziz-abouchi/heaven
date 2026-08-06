const std = @import("std");
const matrix_lib = @import("matrix_lib");
const jit_c = @import("jit_c.zig");
const platform = @import("platform");

// --- Bindings TCC (Native JIT) ---
pub const TCCState = opaque {};
pub const TCC_OUTPUT_MEMORY = 1;
pub const TCC_RELOCATE_AUTO = @as(?*anyopaque, @ptrFromInt(1));
pub extern fn tcc_new() ?*TCCState;
pub extern fn tcc_set_output_type(s: *TCCState, output_type: c_int) c_int;
pub extern fn tcc_set_options(s: *TCCState, str: [*:0]const u8) void;
pub extern fn tcc_compile_string(s: *TCCState, code: [*:0]const u8) c_int;
pub extern fn tcc_relocate(s: *TCCState, ptr: ?*anyopaque) c_int;
pub extern fn tcc_get_symbol(s: *TCCState, name: [*:0]const u8) ?*anyopaque;
pub extern fn tcc_add_symbol(s: *TCCState, name: [*:0]const u8, val: ?*const anyopaque) c_int;
pub extern fn tcc_delete(s: *TCCState) void;

// --- Ajout des bindings POSIX manuels ---
pub extern "c" fn dlopen(path: ?[*:0]const u8, mode: c_int) ?*anyopaque;
pub extern "c" fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;
pub const RTLD_NOW = 2;

// --- External Linker pour le Polyglotte ---
pub const ExternalLinker = struct {
    allocator: std.mem.Allocator,
    loaded_libs: std.StringHashMap(std.DynLib),
    // On stocke le handle brut pour "native" pour éviter les caprices de std.DynLib
    global_raw_handle: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator) ExternalLinker {
        return .{
            .allocator = allocator,
            .loaded_libs = std.StringHashMap(std.DynLib).init(allocator),
            .global_raw_handle = null,
        };
    }

    pub fn loadLibrary(self: *ExternalLinker, path: []const u8) !void {
        if (std.mem.eql(u8, path, "native")) {
            if (self.global_raw_handle == null) {
                // dlopen(NULL) est la clé pour Guix/NixOS : on lie le binaire actuel
                const handle = dlopen(null, RTLD_NOW) orelse return error.GlobalLinkerFailed;
                self.global_raw_handle = handle;
                platform.debug.print("[AUTOFAB] Linker global (Self-Link) initialisé.\n", .{});
            }
            return;
        }

        if (self.loaded_libs.contains(path)) return;
        const lib = try std.DynLib.open(path);
        try self.loaded_libs.put(path, lib);
    }

    pub fn getSymbol(self: *ExternalLinker, lib_path: []const u8, name: [:0]const u8) ?*anyopaque {
        if (std.mem.eql(u8, lib_path, "native")) {
            if (self.global_raw_handle) |h| {
                // On utilise dlsym directement pour le handle brut
                return dlsym(h, name);
            }
            return null;
        }
        if (self.loaded_libs.getPtr(lib_path)) |lib| {
            return lib.lookup(*anyopaque, name);
        }
        return null;
    }
};

pub const XobHeader = extern struct {
    magic: u32 = 0xDEADC0DE,
    code_len: u32,
};

// --- Structures de Métrologie ---
pub const ForgeMetrics = struct {
    input_nodes: u32,
    compilation_time_ns: u64,
    binary_size_bytes: usize,
    target: enum { Native, Wasm, Transpiled },
    pub fn report(self: ForgeMetrics) void {
        const ms = @as(f64, @floatFromInt(self.compilation_time_ns)) / 1_000_000.0;
        platform.debug.print("\n--- [FORGE METRICS] ---\n", .{});
        platform.debug.print("Target: {s}\n", .{@tagName(self.target)});
        platform.debug.print("Time  : {d:.3} ms\n", .{ms});
        platform.debug.print("Size  : {d} bytes\n", .{self.binary_size_bytes});
        platform.debug.print("-----------------------\n", .{});
    }
};

pub const TargetPlatform = enum {
    NativeJit,
    WasmVessel,
    TranspiledC,
};

pub const Directive = struct {
    platform: TargetPlatform,
    optimize_level: u8 = 1,
};

// --- AutoFab Core (Extendu) ---
pub const AutoFab = struct {
    allocator: std.mem.Allocator,
    matrix: *matrix_lib.Matrix,
    bob_name: []const u8,
    linker: ExternalLinker,
    // Remplacement par Unmanaged
    jit_history: std.ArrayListUnmanaged(*TCCState) = .{},
    symbols: std.StringHashMap(*anyopaque),
    loaded_libs: std.StringHashMap(bool),
    jit: jit_c.JitC,

    pub fn init(allocator: std.mem.Allocator, matrix: *matrix_lib.Matrix, name: []const u8) AutoFab {
        return .{
            .allocator = allocator,
            .matrix = matrix,
            .bob_name = name,
            .linker = ExternalLinker.init(allocator),
            .jit_history = .{},
            .symbols = std.StringHashMap(*anyopaque).init(allocator),
            .loaded_libs = std.StringHashMap(bool).init(allocator),
            .jit = jit_c.JitC.init(allocator),
        };
    }

    pub fn deinit(self: *AutoFab) void {
        // Nettoyage de l'historique JIT si nécessaire
        for (self.jit_history.items) |s| {
            tcc_delete(s);
        }
        self.jit_history.deinit(self.allocator);
        self.linker.loaded_libs.deinit();
    }

    pub fn forge(self: *AutoFab, node_id: u32, platform_arg: anytype) !void {
        _ = platform_arg;

        const node = self.matrix.nodes.get(node_id) orelse return;

        if (node != .NativeCode) return;

        const code = node.NativeCode.code;

        try self.jit.compileAndRun(code);
    }

    pub fn oldforge(self: *AutoFab, node_id: matrix_lib.BobId, directive: Directive) !void {
        var timer = try std.time.Timer.start();
        _ = self.matrix.nodes.get(node_id) orelse return error.NodeNotFound;

        const entry_name = self.matrix.getSymbolName(node_id) orelse "main";

        var transpiler = @import("../inference/forge/transpiler.zig").SurvivalTranspiler{
            .allocator = self.allocator,
            .matrix = self.matrix,
        };
        const source = try transpiler.generateRunnableC(node_id);

        var bin_size: usize = 0;
        switch (directive.platform) {
            .NativeJit => {
                try self.executeNativeJIT(source, entry_name, node_id);
                bin_size = source.len;
            },
            .WasmVessel => {
                bin_size = try self.generateWasm(source);
            },
            .TranspiledC => {
                try self.exportToC(source);
                bin_size = source.len;
            },
        }

        const metrics = ForgeMetrics{
            .input_nodes = 1,
            .compilation_time_ns = timer.read(),
            .binary_size_bytes = bin_size,
            .target = switch (directive.platform) {
                .NativeJit => .Native,
                .WasmVessel => .Wasm,
                .TranspiledC => .Transpiled,
            },
        };
        metrics.report();
    }

    fn executeNativeJIT(self: *AutoFab, source: []const u8, entry_symbol: []const u8, root_id: matrix_lib.BobId) !void {
        try self.linker.loadLibrary("native");
        const s = tcc_new() orelse return error.TccInitFailed;
        _ = tcc_set_output_type(s, TCC_OUTPUT_MEMORY);
        tcc_set_options(s, "-fPIC");

        // --- LIAISON INTELLIGENTE : Correction du parcours ---
        // Dans ta Matrix, les edges sont des Nœuds. On itère sur tous les nœuds.
        var it = self.matrix.nodes.iterator();
        while (it.next()) |entry| {
            const node = entry.value_ptr.*;
            if (node == .Edge) {
                const e = node.Edge;
                // Si l'arête part de notre fonction et est un lien de référence ("Ref")
                if (e.source == root_id and std.mem.eql(u8, e.label, "Ref")) {
                    // On récupère la cible (le symbole externe dont on a besoin)
                    if (self.matrix.nodes.get(e.target)) |target_node| {
                        if (target_node == .ExternLink) {
                            const link = target_node.ExternLink;
                            const sym_z = try self.allocator.dupeZ(u8, link.symbol_name);
                            defer self.allocator.free(sym_z);
                            if (self.linker.getSymbol(link.lib_name, sym_z)) |addr| {
                                _ = tcc_add_symbol(s, sym_z, addr);
                            }
                        }
                    }
                }
            }
        }

        _ = tcc_add_symbol(s, "puts", self.linker.getSymbol("native", "puts") orelse @ptrCast(&platform.debug.print));
        _ = tcc_add_symbol(s, "notify_bob", @ptrCast(&bobLogFromC));
        _ = tcc_add_symbol(s, "printf", self.linker.getSymbol("native", "printf") orelse @ptrCast(&platform.debug.print));
        _ = tcc_add_symbol(s, "fflush", self.linker.getSymbol("native", "fflush") orelse null);
        _ = tcc_add_symbol(s, "stdout", self.linker.getSymbol("native", "stdout") orelse null);

        const code_z = try self.allocator.dupeZ(u8, source);
        defer self.allocator.free(code_z);

        if (tcc_compile_string(s, code_z.ptr) != 0) return error.CompileError;
        if (tcc_relocate(s, TCC_RELOCATE_AUTO) < 0) return error.RelocateError;

        // Utilisation de l'allocateur pour l'Unmanaged
        try self.jit_history.append(self.allocator, s);

        const entry_z = try self.allocator.dupeZ(u8, entry_symbol);
        defer self.allocator.free(entry_z);

        if (tcc_get_symbol(s, entry_z.ptr)) |func| {
            const entry_fn: *const fn () callconv(.c) void = @ptrCast(func);
            entry_fn();
        } else if (tcc_get_symbol(s, "main")) |main_ptr| { // Fallback si c'est un main() standard
            const main_fn: *const fn () callconv(.c) void = @ptrCast(main_ptr);
            main_fn();
        } else {
            platform.debug.print("[AUTOFAB ERR] Point d'entrée '{s}' introuvable !\n", .{entry_symbol});
        }
    }

    pub fn synthesizeAndExecute(self: *AutoFab, code: []const u8) !void {
        // 1. Détection du point d'entrée présent dans le code
        var entry_point: []const u8 = "main"; // Par défaut

        if (std.mem.indexOf(u8, code, "heaven_entry") != null) {
            entry_point = "heaven_entry";
        } else if (std.mem.indexOf(u8, code, "main") == null) {
            // 2. Si aucun des deux n'est présent, on force le wrapper heaven_entry
            const wrapped = try std.fmt.allocPrint(self.allocator,
                \\#include <stdio.h>
                \\#include <unistd.h>
                \\void heaven_entry() {{
                \\  {s}
                \\  fflush(stdout);
                \\}}
            , .{code});
            defer self.allocator.free(wrapped);
            return self.executeNativeJIT(wrapped, "heaven_entry", 0);
        }

        // 3. On exécute avec le point d'entrée détecté (main ou heaven_entry)
        try self.executeNativeJIT(code, entry_point, 0);
    }

    pub fn getJITSymbol(self: *AutoFab, name: []const u8) ?*anyopaque {
        // On cherche dans l'historique en partant du plus récent (le dernier)
        if (self.jit_history.items.len == 0) return null;

        const last_idx = self.jit_history.items.len - 1;
        const s = self.jit_history.items[last_idx];

        const name_z = self.allocator.dupeZ(u8, name) catch return null;
        defer self.allocator.free(name_z);

        return tcc_get_symbol(s, name_z);
    }

    fn generateWasm(self: *AutoFab, source: []const u8) !usize {
        const tmp_file = "vessel_gen.c";
        const out_wasm = "vessel_gen.wasm";

        try platform.fs.cwd().writeFile(.{ .sub_path = tmp_file, .data = source });

        // Utilisation du nouveau namespace pour Zig 0.15+
        var child = std.process.Child.init(&[_][]const u8{
            "zig",
            "build-exe",
            tmp_file,
            "-target",
            "wasm32-freestanding",
            "-O",
            "ReleaseSmall",
            "--name",
            "vessel_gen",
        }, self.allocator);

        const term = try child.spawnAndWait();

        if (term == .Exited and term.Exited == 0) {
            const stat = try platform.fs.cwd().statFile(out_wasm);
            platform.debug.print("[AutoFab] Wasm Forge Success: {d} bytes\n", .{stat.size});
            return @intCast(stat.size);
        } else {
            return error.WasmCompilationFailed;
        }
    }

    fn exportToC(self: *AutoFab, source: []const u8) !void {
        _ = self;
        const file = try platform.fs.cwd().createFile("forge_output.c", .{});
        defer file.close();
        try file.writeAll(source);
        platform.debug.print("[AutoFab] Source exported to forge_output.c\n", .{});
    }

    pub fn quickForge(self: *AutoFab, c_code: [:0]const u8) !void {
        try self.linker.loadLibrary("native");
        const s = tcc_new() orelse return error.TccInitFailed;
        defer tcc_delete(s);

        _ = tcc_set_output_type(s, TCC_OUTPUT_MEMORY);

        // Injection des fonctions de base
        _ = tcc_add_symbol(s, "notify_bob", @ptrCast(&bobLogFromC));

        // On lie la libc pour puts, etc.
        if (self.linker.getSymbol("native", "puts")) |puts_addr| {
            _ = tcc_add_symbol(s, "puts", puts_addr);
        }

        if (tcc_compile_string(s, c_code.ptr) != 0) return error.CompileError;
        if (tcc_relocate(s, TCC_RELOCATE_AUTO) < 0) return error.RelocateError;

        const func = tcc_get_symbol(s, "main") orelse return error.SymbolNotFound;
        const main_fn: *const fn () callconv(.c) void = @ptrCast(func);
        main_fn();
    }

    pub fn executeDeterministic(self: *AutoFab, id: u32, code: []const u8) !void {
        // compilation lazy + cache
        const fn_ptr = try self.compileIfNeeded(id, code);
        const func: *const fn () callconv(.c) void = @ptrCast(fn_ptr);
        func();
    }

    fn compileIfNeeded(self: *AutoFab, id: u32, code: []const u8) !*anyopaque {
        if (self.symbols.getPtr(id)) |ptr| {
            return ptr.*;
        }

        // compile réel via TCC
        const fn_ptr = try self.jitCompile(code);

        try self.symbols.put(id, fn_ptr);
        return fn_ptr;
    }

    fn jitCompile(self: *AutoFab, code: []const u8) !*anyopaque {
        const s = tcc_new() orelse return error.TccInitFailed;
        _ = tcc_set_output_type(s, TCC_OUTPUT_MEMORY);

        const code_z = try self.allocator.dupeZ(u8, code);
        defer self.allocator.free(code_z);

        if (tcc_compile_string(s, code_z.ptr) != 0) return error.CompileError;
        if (tcc_relocate(s, TCC_RELOCATE_AUTO) < 0) return error.RelocateError;

        return tcc_get_symbol(s, "main") orelse return error.SymbolNotFound;
    }

    pub fn resolveSymbol(self: *AutoFab, name: []const u8) ?*anyopaque {
        if (self.symbols.get(name)) |ptr| return ptr;

        if (self.linker.getSymbol("native", name)) |ext| {
            self.symbols.put(name, ext) catch {};
            return ext;
        }

        return null;
    }

    pub fn executeSymbol(self: *AutoFab, symbol: []const u8) !void {
        if (self.resolveSymbol(symbol)) |ptr| {
            const f: *const fn () callconv(.c) void = @ptrCast(ptr);
            f();
            return;
        }

        return error.SymbolNotFound;
    }
};

fn bobLogFromC(msg: [*:0]const u8) callconv(.c) void {
    platform.debug.print("\n[BOB-RELAY] {s}\n", .{msg});
}

pub fn estimateCost(node: matrix_lib.BobNode) u32 {
    return switch (node) {
        .Apply => 10,
        .Aggregate => 50,
        .Relation => 20,
        else => 1,
    };
}

pub const ArgumentDispatcher = struct {
    // Cette structure permet de transformer un Node de la Matrix
    // en pointeur compatible C.
    pub fn dispatch(matrix: *matrix_lib.Matrix, node_id: matrix_lib.BobId) ?*anyopaque {
        const node = matrix.nodes.get(node_id) orelse return null;
        return switch (node) {
            .String => |s| @ptrCast(@constCast(s.ptr)), // Passage de string Zig -> char* C
            .RawPointer => |p| p,
            else => null,
        };
    }
};
