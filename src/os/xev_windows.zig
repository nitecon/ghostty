//! Windows IOCP with copyable, shared async notification state.
//!
//! Ghostty copies async handles into mailboxes and stream handlers. IOCP's
//! notifier contains its waiter inline, unlike Unix descriptor-backed handles.
//! Keep that state at a stable address and register the native IOCP watcher
//! directly, avoiding Dynamic.Async.wait's by-value registration.

const std = @import("std");
const native = @import("xev").IOCP;

pub const dynamic = false;
pub const backend = native.backend;
pub const CallbackAction = native.CallbackAction;
pub const Completion = native.Completion;
pub const Loop = native.Loop;
pub const Process = native.Process;
pub const Stream = native.Stream;
pub const Timer = native.Timer;
pub const WriteBuffer = native.WriteBuffer;
pub const WriteError = native.WriteError;
pub const WriteQueue = native.WriteQueue;
pub const WriteRequest = native.WriteRequest;

/// An owning handle with borrowed value copies. As with descriptor-backed xev
/// handles, only the original owner calls deinit, after all waiters/producers stop.
pub const Async = struct {
    state: *native.Async,

    pub const WaitError = native.Async.WaitError;

    /// Allocate one stable notifier; copies retain this same registration state.
    pub fn init() !Async {
        const state = try std.heap.c_allocator.create(native.Async);
        errdefer std.heap.c_allocator.destroy(state);
        state.* = try native.Async.init();
        return .{ .state = state };
    }

    /// Release the owner's notifier after its loop and all borrowed copies stop.
    pub fn deinit(self: *Async) void {
        self.state.deinit();
        std.heap.c_allocator.destroy(self.state);
        self.* = undefined;
    }

    /// Register on the owner loop. The state remains stable when this handle moves.
    pub fn wait(
        self: Async,
        loop: *Loop,
        completion: *Completion,
        comptime Userdata: type,
        userdata: ?*Userdata,
        comptime callback: *const fn (?*Userdata, *Loop, *Completion, WaitError!void) CallbackAction,
    ) void {
        self.state.wait(loop, completion, Userdata, userdata, callback);
    }

    /// Wake the registered loop from any producer holding a borrowed handle copy.
    pub fn notify(self: Async) !void {
        try self.state.notify();
    }
};
