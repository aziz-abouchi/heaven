const std = @import("std");
const platform = @import("platform");

pub const Command = union(enum) {
    AddSymbol: []const u8,
    Unify: struct { a: u32, b: u32 },
    PostMail: struct { target: u32, msg: u32 },
    RequestSync: struct { peer_addr: std.net.Address, last_id: u32 },
    MatrixSync: []const u8,
};

pub const CommandNode = struct {
    data: Command,
    next: ?*CommandNode = null,
};

pub var command_queue = CommandQueue{};

pub const CommandQueue = struct {
    head: ?*CommandNode = null,
    mutex: platform.Thread.Mutex = .{},

    pub fn put(self: *CommandQueue, node: *CommandNode) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        node.next = self.head;
        self.head = node;
    }

    pub fn get(self: *CommandQueue) ?*CommandNode {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.head) |node| {
            self.head = node.next;
            return node;
        }
        return null;
    }

    pub fn takeAll(self: *CommandQueue) ?*CommandNode {
        self.mutex.lock();
        defer self.mutex.unlock();

        const head = self.head;
        self.head = null;
        return head;
    }

    pub fn putBatch(self: *CommandQueue) ?*CommandNode {
        _ = self;
    }
};
