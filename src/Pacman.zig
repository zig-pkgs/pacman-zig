pub const utils = @import("utils.zig");
pub const Config = @import("Pacman/Config.zig");
pub const Transaction = @import("Pacman/Transaction.zig");
pub const log = @import("Pacman/log.zig");
pub const Database = @import("Pacman/Database.zig");
pub const RemoteDatabases = @import("Pacman/RemoteDatabases.zig");
pub const AlpmList = @import("Pacman/alpm_list.zig").AlpmList;

gpa: mem.Allocator,
handle: *c.alpm_handle_t,
config: Config,
thread: std.Thread,
callbacks_set: bool = false,

pub fn init(gpa: mem.Allocator) !Pacman {
    c.console_cursor_hide();
    const signal_fd = try utils.SoftInterrupt.installHandler();

    var pacman: Pacman = .{
        .gpa = gpa,
        .thread = undefined,
        .handle = undefined,
        .config = try .init(gpa, "/etc/pacman"),
    };
    errdefer pacman.config.deinit();

    pacman.config.translate();
    try pacman.config.initAlpm();

    pacman.thread = try std.Thread.spawn(
        .{},
        utils.handleSoftInterrupt,
        .{ signal_fd, pacman.handle, gpa },
    );

    return pacman;
}

pub fn setCallbacks(self: *Pacman) void {
    self.callbacks_set = true;
    self.config.setCallbacks();
}

pub fn deinit(self: *Pacman) void {
    c.console_cursor_show();
    utils.SoftInterrupt.removeHandler();
    self.thread.join();
    self.config.deinit();
}

pub fn remoteDatabases(self: *Pacman) !RemoteDatabases {
    try self.ensureCallbacksSet();
    return try .init(self);
}

pub fn getLocalDb(self: *Pacman) !Database {
    return try Database.getLocal(self);
}

pub fn transaction(self: *Pacman, flags: Transaction.Flags) !Transaction {
    try self.ensureCallbacksSet();
    return .init(self, flags);
}

pub fn ensureCallbacksSet(self: *Pacman) error{CallbacksUnset}!void {
    if (!self.callbacks_set) return error.CallbacksUnset;
}

pub fn getError(self: *Pacman) utils.AlpmError {
    return utils.alpmErrnoToError(self.handle);
}

pub fn getErrorStr(self: *Pacman) [*c]const u8 {
    return c.alpm_strerror(c.alpm_errno(self.handle));
}

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const posix = std.posix;
const testing = std.testing;
const Allocator = mem.Allocator;
const builtin = @import("builtin");
const Pacman = @This();
