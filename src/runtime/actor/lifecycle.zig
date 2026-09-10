const std = @import("std");

pub const ActorState = enum {
    created,
    ready,
    running,
    blocked,
    stopped,
    failed,
};

pub const LifecycleError = error{
    InvalidTransition,
};

pub const Lifecycle = struct {
    state: ActorState = .created,

    pub fn init() Lifecycle {
        return .{
            .state = .created,
        };
    }

    pub fn isTerminal(self: *const Lifecycle) bool {
        return switch (self.state) {
            .stopped, .failed => true,
            else => false,
        };
    }

    pub fn canTransition(
        self: *const Lifecycle,
        next: ActorState,
    ) bool {
        return switch (self.state) {
            .created => switch (next) {
                .ready, .stopped, .failed => true,
                else => false,
            },

            .ready => switch (next) {
                .running, .stopped, .failed => true,
                else => false,
            },

            .running => switch (next) {
                .ready, .blocked, .stopped, .failed => true,
                else => false,
            },

            .blocked => switch (next) {
                .ready, .stopped, .failed => true,
                else => false,
            },

            .stopped, .failed => false,
        };
    }

    pub fn transition(
        self: *Lifecycle,
        next: ActorState,
    ) LifecycleError!void {
        if (!self.canTransition(next)) {
            return LifecycleError.InvalidTransition;
        }

        self.state = next;
    }

    pub fn start(self: *Lifecycle) LifecycleError!void {
        return self.transition(.ready);
    }

    pub fn run(self: *Lifecycle) LifecycleError!void {
        return self.transition(.running);
    }

    pub fn block(self: *Lifecycle) LifecycleError!void {
        return self.transition(.blocked);
    }

    pub fn resumeActor(self: *Lifecycle) LifecycleError!void {
        return self.transition(.ready);
    }

    pub fn stop(self: *Lifecycle) LifecycleError!void {
        return self.transition(.stopped);
    }

    pub fn fail(self: *Lifecycle) LifecycleError!void {
        return self.transition(.failed);
    }
};

test "actor lifecycle — happy path" {
    var lifecycle = Lifecycle.init();

    try std.testing.expectEqual(
        ActorState.created,
        lifecycle.state,
    );

    try lifecycle.start();
    try std.testing.expectEqual(
        ActorState.ready,
        lifecycle.state,
    );

    try lifecycle.run();
    try std.testing.expectEqual(
        ActorState.running,
        lifecycle.state,
    );

    try lifecycle.block();
    try std.testing.expectEqual(
        ActorState.blocked,
        lifecycle.state,
    );

    try lifecycle.resumeActor();
    try std.testing.expectEqual(
        ActorState.ready,
        lifecycle.state,
    );

    try lifecycle.run();
    try lifecycle.stop();

    try std.testing.expectEqual(
        ActorState.stopped,
        lifecycle.state,
    );

    try std.testing.expect(lifecycle.isTerminal());
}

test "actor lifecycle — invalid transition is rejected" {
    var lifecycle = Lifecycle.init();

    try std.testing.expectError(
        LifecycleError.InvalidTransition,
        lifecycle.run(),
    );

    try lifecycle.start();
    try lifecycle.run();
    try lifecycle.stop();

    try std.testing.expectError(
        LifecycleError.InvalidTransition,
        lifecycle.start(),
    );

    try std.testing.expectEqual(
        ActorState.stopped,
        lifecycle.state,
    );
}

test "actor lifecycle — failure is terminal" {
    var lifecycle = Lifecycle.init();

    try lifecycle.start();
    try lifecycle.run();
    try lifecycle.fail();

    try std.testing.expectEqual(
        ActorState.failed,
        lifecycle.state,
    );

    try std.testing.expect(lifecycle.isTerminal());

    try std.testing.expectError(
        LifecycleError.InvalidTransition,
        lifecycle.resumeActor(),
    );
}
