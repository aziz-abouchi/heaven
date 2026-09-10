const std = @import("std");

pub const ActorId = u64;
pub const MessageId = u64;

pub const Message = struct {
    id: MessageId,
    sender: ?ActorId,
    payload: []u8,
};

pub const MailboxError = error{
    Empty,
    Full,
    OutOfMemory,
};

pub const Mailbox = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayListUnmanaged(Message) = .{},
    next_id: MessageId = 1,
    max_messages: ?usize = null,

    pub fn init(allocator: std.mem.Allocator) Mailbox {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Mailbox) void {
        for (self.messages.items) |message| {
            self.allocator.free(message.payload);
        }

        self.messages.deinit(self.allocator);
    }

    pub fn len(self: *const Mailbox) usize {
        return self.messages.items.len;
    }

    pub fn isEmpty(self: *const Mailbox) bool {
        return self.messages.items.len == 0;
    }

    pub fn send(
        self: *Mailbox,
        sender: ?ActorId,
        payload: []const u8,
    ) !MessageId {
        if (self.max_messages) |limit| {
            if (self.messages.items.len >= limit) {
                return MailboxError.Full;
            }
        }

        const owned = try self.allocator.dupe(u8, payload);

        const id = self.next_id;
        self.next_id += 1;

        try self.messages.append(self.allocator, .{
            .id = id,
            .sender = sender,
            .payload = owned,
        });

        return id;
    }

    pub fn receive(self: *Mailbox) !Message {
        if (self.messages.items.len == 0) {
            return MailboxError.Empty;
        }

        return self.messages.orderedRemove(0);
    }

    pub fn peek(self: *const Mailbox) ?*const Message {
        if (self.messages.items.len == 0) {
            return null;
        }

        return &self.messages.items[0];
    }

    pub fn clear(self: *Mailbox) void {
        for (self.messages.items) |message| {
            self.allocator.free(message.payload);
        }

        self.messages.clearRetainingCapacity();
    }
};

test "mailbox — FIFO ordering" {
    var mailbox = Mailbox.init(std.testing.allocator);
    defer mailbox.deinit();

    const id1 = try mailbox.send(1, "first");
    const id2 = try mailbox.send(2, "second");

    try std.testing.expectEqual(@as(MessageId, 1), id1);
    try std.testing.expectEqual(@as(MessageId, 2), id2);
    try std.testing.expectEqual(@as(usize, 2), mailbox.len());

    const first = try mailbox.receive();
    defer std.testing.allocator.free(first.payload);

    try std.testing.expectEqual(id1, first.id);
    try std.testing.expectEqualStrings("first", first.payload);

    const second = try mailbox.receive();
    defer std.testing.allocator.free(second.payload);

    try std.testing.expectEqual(id2, second.id);
    try std.testing.expectEqualStrings("second", second.payload);
}

test "mailbox — empty receive" {
    var mailbox = Mailbox.init(std.testing.allocator);
    defer mailbox.deinit();

    try std.testing.expectError(
        MailboxError.Empty,
        mailbox.receive(),
    );
}

test "mailbox — sender preserved" {
    var mailbox = Mailbox.init(std.testing.allocator);
    defer mailbox.deinit();

    _ = try mailbox.send(42, "hello");

    const message = try mailbox.receive();
    defer std.testing.allocator.free(message.payload);

    try std.testing.expectEqual(
        @as(?ActorId, 42),
        message.sender,
    );
}
