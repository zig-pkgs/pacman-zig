pub const utils = @import("utils.zig");
pub const Config = @import("Pacman/Config.zig");
pub const Transaction = @import("Pacman/Transaction.zig");
pub const log = @import("Pacman/log.zig");
pub const RemoteDatabases = @import("Pacman/RemoteDatabases.zig");
pub const AlpmList = @import("Pacman/alpm_list.zig").AlpmList;

gpa: mem.Allocator,
handle: *c.alpm_handle_t,
config: Config,
thread: std.Thread,

pub fn init(gpa: mem.Allocator) !Pacman {
    c.console_cursor_hide();
    const signal_fd = try utils.SoftInterrupt.installHandler();

    var pacman: Pacman = .{
        .gpa = gpa,
        .thread = undefined,
        .handle = undefined,
        .config = try .init(gpa, "/etc/pacman"),
    };

    try pacman.config.translate();
    try pacman.config.initAlpm();

    pacman.thread = try std.Thread.spawn(
        .{},
        utils.handleSoftInterrupt,
        .{ signal_fd, pacman.handle, gpa },
    );

    return pacman;
}

pub fn deinit(self: *Pacman) void {
    c.console_cursor_show();
    utils.SoftInterrupt.removeHandler();
    self.thread.join();
    const config: *c.config_t = @ptrCast(c.config);
    self.config.deinit();
    self.gpa.destroy(config);
}

pub fn remoteDatabases(self: *Pacman) !RemoteDatabases {
    return try .init(self);
}

pub fn transaction(self: *Pacman) Transaction {
    return .init(self);
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
