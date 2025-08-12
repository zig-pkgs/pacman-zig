pub const Config = @import("Pacman/Config.zig");

pub const InitOptions = struct {
    root_dir: ?[:0]const u8 = null,
    config_file: [:0]const u8 = "/etc/pacman.zon",
    disable_sandbox: bool = false,
    cachedirs: ?[]const []const u8 = null,
};

const cursor_hide_ansicode = "\x1B[?25l";
const cursor_show_ansicode = "\x1B[?25h";

pub const Operation = union(enum) {
    remove: struct {},
    upgrade: struct {},
    query: struct {},
    sync: struct {},
    deptest: struct {},
    database: struct {},
    files: struct {},
};

cb_ctx: callbacks.Context,
config: Config,
gpa: mem.Allocator,
operation: Operation = .{ .sync = .{} },

/// Initializes the Pacman instance. This creates the configuration,
/// sets sane defaults, and parses the main pacman.conf file.
/// The `config_path` is the path to your `pacman.conf`.
pub fn init(gpa: Allocator, options: InitOptions) !Pacman {
    try consoleCursorHide();
    return .{
        .gpa = gpa,
        .cb_ctx = .init(gpa),
        .config = try .parse(gpa, options.config_file),
    };
}

pub fn deinit(self: *Pacman) void {
    self.cb_ctx.deinit();
    self.config.deinit(self.gpa);
    consoleCursorShow() catch {};
}

pub fn setupAlpm(self: *Pacman) !void {
    try self.config.initAlpm();

    // 2. Set all options on the handle, using `try` for cleaner error checks.
    try self.config.setLogFile();
    try self.config.setGpgDir();

    // Set callbacks (assuming they are defined elsewhere, e.g., in a callbacks.zig file)
    self.config.setCallbacks(&self.cb_ctx);

    try self.config.setHookDirs();
}

fn consoleCursorHide() !void {
    if (stdout.isTty()) {
        try stdout.writeAll(cursor_hide_ansicode);
    }
}

fn consoleCursorShow() !void {
    if (stdout.isTty()) {
        try stdout.writeAll(cursor_show_ansicode);
    }
}

const std = @import("std");
const c = @import("c");
const builtin = @import("builtin");
const mem = std.mem;
const posix = std.posix;
const testing = std.testing;
const Pacman = @This();
const Allocator = mem.Allocator;
const callbacks = @import("Pacman/callbacks.zig");
const stdout = std.io.getStdOut();

test {
    var pacman = try Pacman.init(testing.allocator, .{});
    defer pacman.deinit();

    try pacman.setupAlpm();
}
