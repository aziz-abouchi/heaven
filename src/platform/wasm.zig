const std = @import("std");

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

pub const posix = struct {
    pub const SEEK = struct {
        pub const SET = 0;
    };
    pub const STDIN_FILENO = 0;
    pub const STDOUT_FILENO = 1;
    pub const STDERR_FILENO = 2;

    pub fn read(_: i32, _: []u8) !usize {
        return error.NotSupported;
    }
    pub fn write(_: i32, _: []const u8) !usize {
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
};

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

pub const fs = struct {
    pub const File = struct {
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
        pub fn readToEndAlloc(_: File, _: std.mem.Allocator, _: usize) ![]u8 {
            return error.NotSupported;
        }
        pub fn close(_: File) void {}
    };

    ///
    const Storage = std.StringHashMap([]u8);
    var storage: ?Storage = null;

    pub fn init(alloc: std.mem.Allocator) void {
        storage = Storage.init(alloc);
    }

    pub fn readFile(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
        if (storage) |*s| {
            if (s.get(path)) |data| {
                return alloc.dupe(u8, data);
            }
        }
        return error.FileNotFound;
    }

    pub fn writeFile(path: []const u8, data: []const u8) !void {
        if (storage) |*s| {
            try s.put(path, data);
        }
    }

    pub const Dir = struct {
        pub fn openFile(_: Dir, _: []const u8, _: anytype) error{FileNotFound}!File {
            return error.FileNotFound;
        }

        // Stub pour la compatibilité avec le code natif
        pub fn readFileAlloc(_: Dir, _: std.mem.Allocator, _: []const u8, _: usize) ![]u8 {
            return error.NotSupported;
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

    pub fn readFileAlloc(_: std.mem.Allocator, _: []const u8, _: usize) ![]u8 {
        return error.NotSupported;
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

    pub fn readLine(_: std.mem.Allocator) ![]u8 {
        return error.NotImplemented;
    }
};

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
            .allocator = alloc,
            .max_capacity = max_capacity,
        };
    }

    pub fn deinit(self: *MessageQueue) void {
        for (self.buffer.items) |msg| {
            self.allocator.free(msg.payload);
        }
        self.buffer.deinit(self.allocator); // ← Passer l'allocator
    }

    pub fn push(self: *MessageQueue, msg: Message) !void {
        if (self.buffer.items.len >= self.max_capacity) {
            const oldest = self.buffer.orderedRemove(0);
            self.allocator.free(oldest.payload);
        }
        try self.buffer.append(self.allocator, msg); // ← Passer l'allocator
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

    pub fn milliTimestamp() i64 {
        return @intFromFloat(js_performance_now());
    }

    pub fn nanoTimestamp() i128 {
        return @as(i128, @intFromFloat(js_performance_now() * 1_000_000));
    }

    pub fn sleep(ns: u64) void {
        _ = ns;
        // No-op en WASM (on ne peut pas bloquer le thread principal)
    }
};

pub fn allocator() std.mem.Allocator {
    return std.heap.wasm_allocator;
}

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
