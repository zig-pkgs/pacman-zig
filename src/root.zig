//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const c = @import("c");
const builtin = @import("builtin");
const mem = std.mem;
const posix = std.posix;
const testing = std.testing;
const Allocator = mem.Allocator;

// TODO: Add uid check if operation needs root access
pub const Pacman = struct {
    allocator: Allocator,
    // A pointer to the underlying C configuration struct.
    // We will manage its lifecycle carefully.
    config: *c.config_t,

    const Self = @This();

    /// Pacman operation failed.
    pub const Error = error{
        InitFailed,
        OperationFailed,
        AllocationFailed,
    };

    pub const InitOptions = struct {
        root_dir: ?[]const u8 = null,
        config_file: ?[]const u8 = null,
        disable_sandbox: bool = false,
        cachedirs: ?[]const []const u8 = null,
    };

    /// Initializes the Pacman instance. This creates the configuration,
    /// sets sane defaults, and parses the main pacman.conf file.
    /// The `config_path` is the path to your `pacman.conf`.
    pub fn init(allocator: Allocator, options: InitOptions) !Self {
        // 1. Set up terminal and signal handlers
        c.console_cursor_hide();
        c.install_segv_handler();
        c.install_soft_interrupt_handler();

        // config_new() creates the main config struct with default values.
        const config: *c.config_t = c.config_new() orelse return error.InitFailed;
        errdefer _ = c.config_free(config);
        c.config = config; // TODO: get rid of global variable
        config.disable_sandbox = @intFromBool(options.disable_sandbox);

        if (options.root_dir) |root_dir| {
            const path_z = try allocator.dupeZ(u8, root_dir);
            // The C struct takes ownership of this string via strdup.
            defer allocator.free(path_z);
            c.free(config.rootdir);
            config.rootdir = c.strdup(path_z);
        }

        if (options.config_file) |config_file| {
            const path_z = try allocator.dupeZ(u8, config_file);
            // The C struct takes ownership of this string via strdup.
            defer allocator.free(path_z);
            c.free(config.configfile);
            config.configfile = c.strdup(path_z);
        }

        if (options.cachedirs) |cachedirs| {
            for (cachedirs) |cachedir| {
                const cachedir_z = try allocator.dupeZ(u8, cachedir);
                defer allocator.free(cachedir_z);
                config.cachedirs = c.alpm_list_add(config.cachedirs, c.strdup(cachedir_z));
            }
        }

        if (!std.io.getStdOut().isTty()) {
            config.noprogressbar = 1;
        } else {
            c.install_winch_handler();
        }

        // parseconfig() reads the config file and populates the handle with
        // repository info and other essential settings.
        if (c.parseconfig(config.configfile) != 0) {
            return error.InitFailed;
        }

        // Set the user agent, just like the C main function does.
        try setUseragent(allocator);

        return .{
            .config = config,
            .allocator = allocator,
        };
    }

    /// Deinitializes the Pacman instance, freeing all associated C resources.
    pub fn deinit(self: *Self) void {
        // 1. Restore terminal state and remove signal handlers.
        c.console_cursor_show();
        c.remove_soft_interrupt_handler();
        if (self.config.handle != null) {
            _ = c.alpm_release(self.config.handle);
        }
        _ = c.config_free(self.config);
    }

    pub const SyncOptions = struct {
        no_confirm: bool = false,
        refresh: bool = false,
        targets: ?[]const []const u8 = null,
        needed: bool = false,
    };

    /// Synchronizes and installs packages. Corresponds to `-S [targets]`.
    pub fn sync(self: *Self, options: SyncOptions) !void {
        // Convert the Zig slice of strings to a C alpm_list_t.
        var c_targets: ?*c.alpm_list_t = null;
        errdefer freeList(c_targets); // Ensure cleanup on error

        if (options.targets) |targets| {
            for (targets) |target| {
                const target_z = try self.allocator.dupeZ(u8, target);
                defer self.allocator.free(target_z);
                c_targets = c.alpm_list_add(c_targets, c.strdup(target_z));
            }
        }

        if (options.needed) self.config.flags |= c.ALPM_TRANS_FLAG_NEEDED;
        defer {
            if (options.needed) self.config.flags &= c.ALPM_TRANS_FLAG_NEEDED;
        }

        self.config.op_s_sync = @intFromBool(options.refresh);
        self.config.noconfirm = @intFromBool(options.no_confirm);

        // Call the actual C function for the sync operation.
        if (c.pacman_sync(c_targets) != 0) {
            return error.OperationFailed;
        }

        // Clean up the list now that the operation is complete.
        freeList(c_targets);
    }

    pub const UpgradeOptions = struct {
        no_confirm: bool = false,
        targets: ?[]const []const u8 = null,
    };

    pub fn upgrade(self: *Self, options: UpgradeOptions) !void {
        // Convert the Zig slice of strings to a C alpm_list_t.
        var c_targets: ?*c.alpm_list_t = null;
        errdefer freeList(c_targets); // Ensure cleanup on error

        if (options.targets) |targets| {
            for (targets) |target| {
                const target_z = try self.allocator.dupeZ(u8, target);
                defer self.allocator.free(target_z);
                c_targets = c.alpm_list_add(c_targets, c.strdup(target_z));
            }
        }

        self.config.noconfirm = @intFromBool(options.no_confirm);

        // Call the actual C function for the sync operation.
        if (c.pacman_upgrade(c_targets) != 0) {
            return error.OperationFailed;
        }

        // Clean up the list now that the operation is complete.
        freeList(c_targets);
    }

    pub const RemoveOptions = struct {
        no_confirm: bool = false,
        targets: ?[]const []const u8 = null,
    };

    /// Removes packages. Corresponds to `-R [targets]`.
    pub fn remove(self: *Self, options: RemoveOptions) !void {
        // Convert the Zig slice of strings to a C alpm_list_t.
        var c_targets: ?*c.alpm_list_t = null;
        errdefer freeList(c_targets); // Ensure cleanup on error

        if (options.targets) |targets| {
            for (targets) |target| {
                const target_z = try self.allocator.dupeZ(u8, target);
                defer self.allocator.free(target_z);
                c_targets = c.alpm_list_add(c_targets, c.strdup(target_z));
            }
        }

        self.config.noconfirm = @intFromBool(options.no_confirm);

        // Call the actual C function for the sync operation.
        if (c.pacman_remove(c_targets) != 0) {
            return error.OperationFailed;
        }

        // Clean up the list now that the operation is complete.
        freeList(c_targets);
    }
};

fn freeList(p: [*c]c.alpm_list_t) void {
    c.alpm_list_free_inner(p, c.free);
    c.alpm_list_free(p);
    //p = null;
}

fn setUseragent(gpa: Allocator) !void {
    const un = posix.uname();

    const version = c.alpm_version();
    const agent_str = try std.fmt.allocPrint(
        gpa,
        "pacman/{s} ({s} {s}) libalpm/{s}",
        .{
            "7.0.0",
            un.sysname,
            un.machine,
            version,
        },
    );
    defer gpa.free(agent_str);

    var envmap = try std.process.getEnvMap(gpa);
    defer envmap.deinit();

    try envmap.put("HTTP_USER_AGENT", agent_str);
}

test {
    var pacman: Pacman = try .init(testing.allocator, .{
        .config_file = "/etc/pacman.conf",
        .cachedirs = &.{"/var/cache/pacman/pkg"},
    });
    defer pacman.deinit();

    try pacman.sync(.{
        .refresh = true,
        .no_confirm = true,
        .needed = true,
    });
}
