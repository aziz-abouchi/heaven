const std = @import("std");
const platform = @import("platform");

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

pub const MessageQueue = struct {
    buffer: std.ArrayListUnmanaged(Message) = .{},
    allocator: std.mem.Allocator,
    max_capacity: usize,
    mutex: MutexType = .{},

    const builtin = @import("builtin");
    const MutexType = if (builtin.target.cpu.arch == .wasm32) WasmMutex else StdMutex;

    const WasmMutex = struct {
        pub fn lock(_: *WasmMutex) void {}
        pub fn unlock(_: *WasmMutex) void {}
        pub fn tryLock(_: *WasmMutex) bool {
            return true;
        }
    };

    const StdMutex = platform.Thread.Mutex;

    pub fn init(allocator: std.mem.Allocator, max_capacity: usize) MessageQueue {
        return .{
            .allocator = allocator,
            .max_capacity = max_capacity,
        };
    }

    pub fn deinit(self: *MessageQueue) void {
        for (self.buffer.items) |msg| {
            self.allocator.free(msg.payload);
        }
        self.buffer.deinit(self.allocator);
    }

    pub fn push(self: *MessageQueue, msg: Message) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.buffer.items.len >= self.max_capacity) {
            const oldest = self.buffer.orderedRemove(0);
            self.allocator.free(oldest.payload);
        }
        try self.buffer.append(self.allocator, msg);
    }

    pub fn pop(self: *MessageQueue) ?Message {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.buffer.items.len == 0) return null;
        return self.buffer.orderedRemove(0);
    }

    pub fn len(self: *const MessageQueue) usize {
        return self.buffer.items.len;
    }
};
