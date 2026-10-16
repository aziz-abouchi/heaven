// HEAVEN:io_console shim cross-cible (API minimale).
pub const io_console = struct {
    pub var debug_enabled: bool = false;
};

const std = @import("std");
pub const target = @import("target.zig");

// Stub profiler pour WASM
pub const profiler = struct {
    pub const ResourceUsage = struct {
        utime: struct { sec: i64 = 0, usec: i64 = 0 } = .{},
        stime: struct { sec: i64 = 0, usec: i64 = 0 } = .{},
        maxrss: u64 = 0,
    };
    pub fn getResourceUsage() ResourceUsage {
        return .{};
    }
};

// readEnergyUJ doit être un error union pour que `catch 0` marche
pub fn readEnergyUJ() error{Unsupported}!u64 {
    return error.Unsupported;
}


/// Debug conditionnel : activé par HEAVEN_DEBUG=1
pub fn dbg(comptime fmt: []const u8, args: anytype) void {
    if (io_console.debug_enabled) debug.print(fmt, args);
}

// On définit le type localement pour éviter la dépendance circulaire avec driver.zig
pub const NetworkDriver = struct {
    send_fn: *const fn (ctx: *anyopaque, data: []const u8) void,
    ctx: *anyopaque,
};

pub fn init() void {}
pub fn deinit() void {}

// ═══════════════════════════════════════════════════════════
// IMPORTS JAVASCRIPT (fonctions JS appelées par Zig via WASM)
// ═══════════════════════════════════════════════════════════

extern fn js_console_log(ptr: [*]const u8, len: usize) void;
extern fn js_console_error(ptr: [*]const u8, len: usize) void;
extern fn js_websocket_connect(ptr: [*]const u8, len: usize) void;
extern fn js_websocket_send(ptr: [*]const u8, len: usize) void;
extern fn js_rtc_connect(ptr: [*]const u8, len: usize) void;
extern fn js_rtc_send(peer_id_ptr: [*]const u8, peer_id_len: usize, data_ptr: [*]const u8, data_len: usize) void;
extern fn js_drain_message_queue() u32;
extern fn js_get_peer_id(msg_id: u32, out_ptr: [*]u8) void;
extern fn js_get_msg_type(msg_id: u32) u8;
extern fn js_get_timestamp(msg_id: u32) u64;
extern fn js_get_payload_ptr(msg_id: u32) u32;
extern fn js_get_payload_len(msg_id: u32) u32;
extern fn js_free_message(msg_id: u32) void;
pub extern "env" fn js_log(ptr: [*]const u8, len: usize) void;

// ═══════════════════════════════════════════════════════════
// POSIX STUBS (compatibilité avec le code existant)
// ═══════════════════════════════════════════════════════════

extern fn js_write_stdout(ptr: [*]const u8, len: usize) void;
extern fn js_write_stderr(ptr: [*]const u8, len: usize) void;

pub const posix = struct {
    pub const STDIN_FILENO = 0;
    pub const STDOUT_FILENO = 1;
    pub const STDERR_FILENO = 2;

    // Types reseau (compat std.posix pour engine_expr.zig)
    pub const socket_t = i32;
    pub const socklen_t = u32;

    pub fn write(fd: i32, bytes: []const u8) !usize {
        switch (fd) {
            STDOUT_FILENO => js_write_stdout(bytes.ptr, bytes.len),
            STDERR_FILENO => js_write_stderr(bytes.ptr, bytes.len),
            else => return error.NotSupported,
        }
        return bytes.len;
    }

    pub const SEEK = struct {
        pub const SET = 0;
    };

    pub fn read(_: i32, _: []u8) !usize {
        return error.NotSupported;
    }
    pub fn socket(_: u32, _: u32, _: u32) !i32 {
        return error.NotSupported;
    }
    pub fn bind(_: i32, _: *const anyopaque, _: u32) !void {
        return error.NotSupported;
    }
    pub fn fork() !i32 {
        return error.NotSupported;
    }
    pub fn accept(_: socket_t, _: *anyopaque, _: *socklen_t, _: u32) !socket_t {
        return error.NotSupported;
    }
    pub fn close(_: socket_t) void {
        // no-op en wasm
    }
    /// Test whether a file descriptor refers to a terminal.
    /// En wasm freestanding : pas de TTY.
    pub fn isatty(_: i32) bool {
        return false;
    }
};

// ═══════════════════════════════════════════════════════════
// ENVIRONMENT STUB (WASM Freestanding)
// ═══════════════════════════════════════════════════════════

/// Wrapper uniforme cross-platform : delegue au VFS JS.
pub fn readFileAllocCwd(alloc: std.mem.Allocator, p: []const u8, max: usize) ![]u8 {
    return fs.readFileAlloc(alloc, p, max);
}

/// Reseau : interface uniforme cross-platform.
/// En wasm32-freestanding, toute operation reseau est indisponible
/// (les WebSockets passent par les externs js_websocket_*).
pub const net = struct {
    // HEAVEN:NET_CONNECT_WASM — stubs (pas de TCP client en browser)

    // D-SH4 : UDP raw syscalls. Pas de support en V0.

    pub fn setRecvTimeout(_: i64, _: u64) void {}

    pub fn socketUdp() i64 { return -1; }
    pub fn sendtoUdp(_: i64, _: []const u8, _: u16, _: []const u8) i64 { return -1; }
    pub fn recvfromUdp(_: i64, _: []u8) i64 { return -1; }

    pub fn socketTcp() i64 {
        return -1;
    }

    pub fn connectTcp(_: []const u8, _: u16) !i64 {
        return error.NotSupported;
    }

    pub fn listenTcp(_: u16) !i64 {
        return error.NotSupported;
    }
    pub fn accept(_: i64) !i64 {
        return error.NotSupported;
    }
    pub fn read(_: i64, _: []u8) !usize {
        return error.NotSupported;
    }
    pub fn write(_: i64, _: []const u8) !usize {
        return error.NotSupported;
    }
    pub fn close(_: i64) void {
        // no-op en wasm
    }
};

pub fn getenv(_: []const u8) ?[]const u8 {
    return null;
}

// ═══════════════════════════════════════════════════════════
// THREAD ABSTRACTION (WASM Web - synchrone)
// ═══════════════════════════════════════════════════════════

pub const Thread = struct {
    pub const Mutex = struct {
        pub fn lock(_: *Mutex) void {}
        pub fn unlock(_: *Mutex) void {}
        pub fn tryLock(_: *Mutex) bool {
            return true;
        }
    };

    pub const SpawnConfig = struct {};

    pub fn spawn(_: SpawnConfig, comptime func: anytype, args: anytype) !Thread {
        // En WASM, on exécute la fonction de manière synchrone
        @call(.{}, func, args);
        return Thread{};
    }

    pub fn join(_: Thread) void {}
    pub fn detach(_: Thread) void {}
};

// ═══════════════════════════════════════════════════════════
// FILESYSTEM ABSTRACTION (WASM Web - mémoire volatile)
// ═══════════════════════════════════════════════════════════

extern fn js_vfs_read_file(ptr: [*]const u8, len: usize) usize;
extern fn js_vfs_copy_buffer(out_ptr: [*]u8, len: usize) void;

pub const fs = struct {
    pub const path = struct {
        pub fn basename(p: []const u8) []const u8 {
            return std.fs.path.basename(p);
        }
        pub fn isAbsolute(p: []const u8) bool {
            return p.len > 0 and p[0] == '/';
        }
        pub fn join(alloc: std.mem.Allocator, paths: []const []const u8) ![]u8 {
            return std.fs.path.join(alloc, paths);
        }
    };

    // VFS ou bridge avec le Host JS
    pub fn readFileAlloc(alloc: std.mem.Allocator, path_str: []const u8, max_size: usize) ![]u8 {
        _ = max_size;
        const len = js_vfs_read_file(path_str.ptr, path_str.len);
        if (len == 0) return error.FileNotFound;

        const buf = try alloc.alloc(u8, len);
        js_vfs_copy_buffer(buf.ptr, len);
        return buf;
    }
    pub fn join(alloc: std.mem.Allocator, paths: []const []const u8) ![]u8 {
        return std.fs.path.join(alloc, paths);
    }


    pub const File = struct {
        // HEAVEN:FILE_VFS_CONTENT - contenu en memoire (VFS)
        content: []u8 = &.{},

        pub const OpenError = error{
            FileNotFound,
            PermissionDenied,
            InputOutput,
            SystemResources,
            IsDir,
            OperationAborted,
            BrokenPipe,
            ConnectionResetByPeer,
            ConnectionTimedOut,
            NotOpenForReading,
            SocketNotConnected,
            WouldBlock,
            Canceled,
            AccessDenied,
            ProcessNotFound,
            LockViolation,
            Unexpected,
            FileTooBig,
        };
        pub const ReadError = OpenError;

        pub fn read(_: File, _: []u8) ReadError!usize {
            return error.ReadError;
        }
        pub fn readToEndAlloc(self: File, alloc: std.mem.Allocator, _: usize) ![]u8 {
            // HEAVEN:FILE_VFS_CONTENT - duplique (le File garde sa propre copie)
            return alloc.dupe(u8, self.content);
        }
        pub fn close(self: File) void {
            if (self.content.len > 0) std.heap.wasm_allocator.free(self.content);
        }
        pub fn writeAll(self: File, bytes: []const u8) anyerror!void {
            _ = self;
            _ = bytes;
            // Stub pour WASM freestanding : à adapter si tu rediriges vers
            // un buffer mémoire, la console JS ou un hôte WASI.
        }
    };

    ///
    const Storage = std.StringHashMap([]u8);
    var storage: ?Storage = null;

    pub fn init(alloc: std.mem.Allocator) void {
        storage = Storage.init(alloc);
    }

    pub fn readFile(alloc: std.mem.Allocator, pathw: []const u8) ![]u8 {
        if (storage) |*s| {
            if (s.get(pathw)) |data| {
                return alloc.dupe(u8, data);
            }
        }
        return error.FileNotFound;
    }

    pub fn writeFile(pathw: []const u8, data: []const u8) !void {
        if (storage) |*s| {
            try s.put(pathw, data);
        }
    }

    pub const Dir = struct {
        // HEAVEN:OPENFILE_VFS - branche sur le VFS
        pub fn openFile(_: Dir, path_str: []const u8, _: anytype) !File {
            const len = js_vfs_read_file(path_str.ptr, path_str.len);
            if (len == 0) return error.FileNotFound;
            const buf = try std.heap.wasm_allocator.alloc(u8, len);
            js_vfs_copy_buffer(buf.ptr, len);
            return File{ .content = buf };
        }

        // HEAVEN:DIR_READFILE_VFS - copie inline de fs.readFileAlloc (VFS)
        // (deleguer par nom serait ambigu : Dir.readFileAlloc shadow
        //  le fs.readFileAlloc du parent)
        pub fn readFileAlloc(_: Dir, alloc: std.mem.Allocator, path_str: []const u8, max: usize) ![]u8 {
            _ = max;
            const len = js_vfs_read_file(path_str.ptr, path_str.len);
            if (len == 0) return error.FileNotFound;
            const buf = try alloc.alloc(u8, len);
            js_vfs_copy_buffer(buf.ptr, len);
            return buf;
        }

        pub fn createFile(_: Dir, _: []const u8, _: anytype) error{NotSupported}!File {
            return error.NotSupported;
        }

        pub fn writeFile(_: Dir, _: []const u8, _: []const u8) !void {
            return error.NotSupported;
        }
    };

    pub fn cwd() Dir {
        return Dir{};
    }

    pub fn writeFileAlloc(_: std.mem.Allocator, _: []const u8, _: []const u8) !void {
        return error.NotSupported;
    }
    pub fn openDirAbsolute(_: std.mem.Allocator, _: []const u8) !Dir {
        return error.NotSupported;
    }
};

// ═══════════════════════════════════════════════════════════
// I/O ABSTRACTION (WASM Web - console.log)
// ═══════════════════════════════════════════════════════════

pub const io = struct {
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        var buf: [4096]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, fmt, args) catch "ERROR";
        js_console_log(str.ptr, str.len);
    }

    pub fn readLine(alloc: std.mem.Allocator) ![]u8 {
        if (!repl_has_data) return error.WouldBlock;
        repl_has_data = false;
        return alloc.dupe(u8, repl_buffer[0..repl_len]);
    }
};
pub fn readLine(alloc: std.mem.Allocator) ![]u8 {
    return io.readLine(alloc);
}

// ═══════════════════════════════════════════════════════════
// DEBUG ABSTRACTION (WASM Web - console.error)
// ═══════════════════════════════════════════════════════════

pub const debug = struct {
    pub fn assert(condition: bool) void {
        if (!condition) {
            const msg = "Assertion failed";
            js_console_error(msg.ptr, msg.len);
            @panic("Assertion failed");
        }
    }

    pub fn print(comptime fmt: []const u8, args: anytype) void {
        var buf: [4096]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, fmt, args) catch "ERROR";
        js_console_error(str.ptr, str.len);
    }
};

// ═══════════════════════════════════════════════════════════
// NETWORK ABSTRACTION (WASM Web - WebSocket + WebRTC via JS)
// ═══════════════════════════════════════════════════════════

pub const Network = struct {
    pub fn init(_: std.mem.Allocator) !Network {
        return Network{};
    }

    // WebSocket (signaling)
    pub fn connectToSignaling(self: *Network, url: []const u8) !void {
        _ = self;
        js_websocket_connect(url.ptr, url.len);
    }

    pub fn announceNode(self: *Network, capabilities: []const u8) !void {
        _ = self;
        js_websocket_send(capabilities.ptr, capabilities.len);
    }

    pub fn discoverPeers(self: *Network) ![][]const u8 {
        _ = self;
        // TODO: Parser le JSON retourné par JavaScript
        return &[_][]const u8{};
    }

    // WebRTC (data plane)
    pub fn connectToPeer(self: *Network, peer_id: []const u8) !void {
        _ = self;
        js_rtc_connect(peer_id.ptr, peer_id.len);
    }

    pub fn sendToPeer(self: *Network, peer_id: []const u8, data: []const u8) !void {
        _ = self;
        js_rtc_send(peer_id.ptr, peer_id.len, data.ptr, data.len);
    }

    pub fn receiveFromPeer(self: *Network, peer_id: []const u8) ![]const u8 {
        _ = self;
        _ = peer_id;
        return error.NotImplemented;
    }

    // Polling non-bloquant pour la tick loop
    pub fn pollMessages(self: *Network, queue: anytype) !void {
        _ = self;

        const msg_id = js_drain_message_queue();
        if (msg_id == 0) return;

        // Lire le peer_id (16 bytes)
        var peer_id: [16]u8 = undefined;
        js_get_peer_id(msg_id, &peer_id);

        const msg_type = js_get_msg_type(msg_id);
        const timestamp = js_get_timestamp(msg_id);
        const payload_ptr = js_get_payload_ptr(msg_id);
        const payload_len = js_get_payload_len(msg_id);

        // Copier le payload depuis la mémoire WASM
        const payload = @as([*]const u8, @ptrFromInt(payload_ptr))[0..payload_len];
        const payload_copy = try queue.allocator.dupe(u8, payload);

        try queue.push(.{
            .peer_id = peer_id,
            .msg_type = @enumFromInt(msg_type),
            .payload = payload_copy,
            .timestamp = timestamp,
        });

        js_free_message(msg_id);
    }
};

pub const MessageQueue = struct {
    buffer: std.ArrayListUnmanaged(Message),
    alloc: std.mem.Allocator,
    max_capacity: usize,

    pub const Message = struct {
        peer_id: [16]u8,
        msg_type: MessageType,
        payload: []const u8,
        timestamp: u64,
    };

    pub const MessageType = enum(u8) {
        handshake = 1,
        egraph_sync = 2,
        proof_request = 3,
        proof_result = 4,
        work_steal_request = 5,
        work_steal_response = 6,
        _,
    };

    pub fn init(alloc: std.mem.Allocator, max_capacity: usize) MessageQueue {
        return .{
            .buffer = .{}, // ArrayListUnmanaged s'initialise vide
            .alloc = alloc,
            .max_capacity = max_capacity,
        };
    }

    pub fn deinit(self: *MessageQueue) void {
        for (self.buffer.items) |msg| {
            self.alloc.free(msg.payload);
        }
        self.buffer.deinit(self.alloc); // ← Passer l'allocator
    }

    pub fn push(self: *MessageQueue, msg: Message) !void {
        if (self.buffer.items.len >= self.max_capacity) {
            const oldest = self.buffer.orderedRemove(0);
            self.alloc.free(oldest.payload);
        }
        try self.buffer.append(self.alloc, msg); // ← Passer l'allocator
    }

    pub fn pop(self: *MessageQueue) ?Message {
        if (self.buffer.items.len == 0) return null;
        return self.buffer.orderedRemove(0);
    }

    pub fn len(self: *const MessageQueue) usize {
        return self.buffer.items.len;
    }
};

pub const time = struct {
    // En WASM, on utilise performance.now() via JS
    extern fn js_performance_now() f64;

    pub const ns_per_s: u64 = 1_000_000_000;
    pub const ns_per_ms: u64 = 1_000_000;
    pub const ns_per_us: u64 = 1_000;

    pub fn milliTimestamp() i64 {
        return @intFromFloat(js_performance_now());
    }

    pub fn nanoTimestamp() i128 {
        return @as(i128, @intFromFloat(js_performance_now() * 1_000_000));
    }

    pub fn sleep(ns: u64) void {
        _ = ns;
        // No-op en WASM
    }
};

pub const allocator = std.heap.wasm_allocator;

// Déclarations des fonctions importées depuis JS
extern "js" fn js_send(ptr: [*]const u8, len: usize) void;

fn wasm_send(ctx: *anyopaque, data: []const u8) void {
    _ = ctx; // Pas besoin de contexte pour le JS global
    js_send(data.ptr, data.len);
}

pub fn createWasmDriver() NetworkDriver {
    return .{
        .send_fn = wasm_send,
        .ctx = undefined,
    };
}

extern fn wasm_entry_process_input(ptr: [*]const u8, len: usize) void;

export fn wasm_receive_data(ptr: [*]const u8, len: usize) void {
    // On délègue au point d'entrée qui, lui, possède l'instance "heaven"
    wasm_entry_process_input(ptr, len);
}

/// ShellParser WASM : stub qui délègue au fallback bridge.importExpr.
pub const ts = void; // pas de tree-sitter en WASM freestanding

pub const shell_parser_types = @import("shell_parser_types");

/// ShellParser WASM : stub qui délègue au fallback bridge.importExpr.
pub const ShellParser = struct {
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) shell_parser_types.ParseError!ShellParser {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *ShellParser) void {
        _ = self;
    }

    pub fn parse(self: *ShellParser, source: []const u8) shell_parser_types.ParseError!shell_parser_types.Matrix {
        _ = self;
        _ = source;
        return shell_parser_types.ParseError.NotSupported;
    }

    pub fn reset(self: *ShellParser) void {
        _ = self;
    }
};

/// MultiParser WASM : stub multi-langage (même interface que le natif)
pub const MultiParser = struct {
    lang: shell_parser_types.Language,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, lang: shell_parser_types.Language) shell_parser_types.ParseError!MultiParser {
        return .{ .lang = lang, .alloc = alloc };
    }

    pub fn parse(self: *MultiParser, source: []const u8) shell_parser_types.ParseError!shell_parser_types.Matrix {
        _ = self;
        _ = source;
        return shell_parser_types.ParseError.NotSupported;
    }

    pub fn reset(self: *MultiParser) void {
        _ = self;
    }

    pub fn deinit(self: *MultiParser) void {
        _ = self;
    }
};

// Storage statique pour les entrées REPL
var repl_buffer: [4096]u8 = undefined;
var repl_len: usize = 0;
var repl_has_data: bool = false;

/// Reçoit les entrées clavier transmises depuis la page REPL
export fn wasm_inject_repl_input(ptr: [*]const u8, len: usize) void {
    const copy_len = @min(len, repl_buffer.len);
    @memcpy(repl_buffer[0..copy_len], ptr[0..copy_len]);
    repl_len = copy_len;
    repl_has_data = true;
}

// Bindings déclarés côté JS pour le Dashboard
extern fn js_emit_metrics(egraph_classes: u32, store_nodes: u32, msg_count: u64) void;

const _top_js_console_log = js_console_log;
const _top_js_console_error = js_console_error;
const _top_js_websocket_connect = js_websocket_connect;
const _top_js_websocket_send = js_websocket_send;
const _top_js_rtc_connect = js_rtc_connect;
const _top_js_rtc_send = js_rtc_send;
const _top_js_drain_message_queue = js_drain_message_queue;
const _top_js_get_peer_id = js_get_peer_id;
const _top_js_get_msg_type = js_get_msg_type;
const _top_js_get_timestamp = js_get_timestamp;
const _top_js_get_payload_ptr = js_get_payload_ptr;
const _top_js_get_payload_len = js_get_payload_len;
const _top_js_free_message = js_free_message;
const _top_js_write_stdout = js_write_stdout;
const _top_js_write_stderr = js_write_stderr;
const _top_js_vfs_read_file = js_vfs_read_file;
const _top_js_vfs_copy_buffer = js_vfs_copy_buffer;
const _top_js_emit_metrics = js_emit_metrics;

// HEAVEN:WASM_FINAL - namespace attendu par wasm_entry.zig
pub const js_env = struct {
    pub const js_console_log = _top_js_console_log;
    pub const js_console_error = _top_js_console_error;
    pub const js_websocket_connect = _top_js_websocket_connect;
    pub const js_websocket_send = _top_js_websocket_send;
    pub const js_rtc_connect = _top_js_rtc_connect;
    pub const js_rtc_send = _top_js_rtc_send;
    pub const js_drain_message_queue = _top_js_drain_message_queue;
    pub const js_get_peer_id = _top_js_get_peer_id;
    pub const js_get_msg_type = _top_js_get_msg_type;
    pub const js_get_timestamp = _top_js_get_timestamp;
    pub const js_get_payload_ptr = _top_js_get_payload_ptr;
    pub const js_get_payload_len = _top_js_get_payload_len;
    pub const js_free_message = _top_js_free_message;
    pub const js_write_stdout = _top_js_write_stdout;
    pub const js_write_stderr = _top_js_write_stderr;
    pub const js_vfs_read_file = _top_js_vfs_read_file;
    pub const js_vfs_copy_buffer = _top_js_vfs_copy_buffer;
    pub fn js_performance_now() f64 { return 0.0; }
    pub const js_emit_metrics = _top_js_emit_metrics;
    pub fn js_broadcast_proof_request(_: [*]const u8, _: usize) void {}
};
