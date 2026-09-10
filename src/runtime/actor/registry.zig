const std = @import("std");
const actor_mod = @import("actor");

const Actor = actor_mod.Actor;
const ActorId = actor_mod.ActorId;

pub const RegistryError = error{
    ActorAlreadyExists,
    ActorNotFound,
    OutOfMemory,
};

pub const ActorRegistry = struct {
    allocator: std.mem.Allocator,
    actors: std.AutoHashMapUnmanaged(ActorId, *Actor) = .{},

    pub fn init(allocator: std.mem.Allocator) ActorRegistry {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ActorRegistry) void {
        self.actors.deinit(self.allocator);
    }

    pub fn register(
        self: *ActorRegistry,
        actor: *Actor,
    ) !void {
        if (self.actors.contains(actor.id)) {
            return RegistryError.ActorAlreadyExists;
        }

        try self.actors.put(
            self.allocator,
            actor.id,
            actor,
        );
    }

    pub fn unregister(
        self: *ActorRegistry,
        actor_id: ActorId,
    ) !*Actor {
        const actor = self.actors.get(actor_id) orelse {
            return RegistryError.ActorNotFound;
        };

        _ = self.actors.remove(actor_id);
        return actor;
    }

    pub fn get(
        self: *ActorRegistry,
        actor_id: ActorId,
    ) ?*Actor {
        return self.actors.get(actor_id);
    }

    pub fn count(self: *const ActorRegistry) usize {
        return self.actors.count();
    }
};

test "actor registry — register and lookup" {
    var actor = Actor.init(std.testing.allocator, 42);
    defer actor.deinit();

    var registry = ActorRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(&actor);

    try std.testing.expectEqual(
        @as(usize, 1),
        registry.count(),
    );

    const found = registry.get(42) orelse {
        return error.ActorNotFound;
    };

    try std.testing.expectEqual(&actor, found);
}

test "actor registry — duplicate actor rejected" {
    var actor1 = Actor.init(std.testing.allocator, 42);
    defer actor1.deinit();

    var actor2 = Actor.init(std.testing.allocator, 42);
    defer actor2.deinit();

    var registry = ActorRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(&actor1);

    try std.testing.expectError(
        RegistryError.ActorAlreadyExists,
        registry.register(&actor2),
    );
}
