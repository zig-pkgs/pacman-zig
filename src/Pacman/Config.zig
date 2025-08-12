handle: *c.alpm_handle_t,
no_progressbar: bool = false,
sync: struct {
    download_only: bool = false,
} = .{},
schema: Schema,

pub const Schema = struct {
    options: Options = .{},
    repositories: []Repository,

    pub fn parse(gpa: mem.Allocator, config_path: [:0]const u8) !Schema {
        var schema = try parseZonFromPath(Schema, gpa, config_path);

        for (schema.repositories) |*repository| {
            if (repository.include) |include| {
                const servers = try parseZonFromPath([]const [:0]const u8, gpa, include);
                repository.servers = servers;
            }
        }

        try schema.options.setDefaults(gpa);

        return schema;
    }

    pub fn deinit(self: *Schema, gpa: mem.Allocator) void {
        zon.parse.free(gpa, self.*);
    }
};

pub const Options = struct {
    root_dir: ?[:0]const u8 = null,
    db_path: ?[:0]const u8 = null,
    cache_dir: ?[:0]const u8 = null,
    log_file: ?[:0]const u8 = null,
    gpg_dir: ?[:0]const u8 = null,
    hook_dir: ?[:0]const u8 = null,

    hold_packages: ?[]const [:0]const u8 = null,
    architecture: Architecture = .auto,
    check_space: bool = true,
    default_sig_level: SigLevel = .{},
    local_file_sig_level: SigLevel = .{},
    remote_file_sig_level: SigLevel = .{},

    fn setDefaults(self: *Options, gpa: mem.Allocator) !void {
        if (self.root_dir) |root_dir| {
            self.db_path = try std.fs.path.joinZ(gpa, &.{
                root_dir,
                c.DBPATH,
            });
            self.log_file = try std.fs.path.joinZ(gpa, &.{
                root_dir,
                c.LOGFILE,
            });
        } else {
            self.root_dir = try gpa.dupeZ(u8, c.ROOTDIR);
            self.db_path = try gpa.dupeZ(u8, c.DBPATH);
            self.log_file = try gpa.dupeZ(u8, c.LOGFILE);
        }
        self.gpg_dir = try gpa.dupeZ(u8, c.GPGDIR);
        self.hook_dir = try gpa.dupeZ(u8, c.HOOKDIR);
    }
};

pub const SigLevel = struct {
    package: VerificationLevel = .required,
    database: VerificationLevel = .optional,
    trust_level: TrustLevel = .trusted_only,
};

pub const VerificationLevel = enum {
    never,
    optional,
    required,
};

pub const TrustLevel = enum {
    trust_all,
    trusted_only,
};

pub const Architecture = enum {
    auto,
    x86_64,
    aarch64,
};

pub const Repository = struct {
    name: [:0]const u8,
    include: ?[:0]const u8 = null,
    servers: ?[]const [:0]const u8 = null,
    cached_servers: ?[]const [:0]const u8 = null,
    sig_level: SigLevel = .{},
    usage: Usage = .all,

    pub const Usage = enum {
        sync,
        search,
        install,
        upgrade,
        all,
    };
};

pub fn parse(gpa: mem.Allocator, config_path: [:0]const u8) !Config {
    return .{
        .handle = undefined,
        .schema = try Schema.parse(gpa, config_path),
    };
}

pub fn deinit(self: *Config, gpa: mem.Allocator) void {
    self.schema.deinit(gpa);
}

pub fn initAlpm(self: *Config) !void {
    var err: c.alpm_errno_t = 0;
    const options = self.schema.options;
    const handle_maybe = c.alpm_initialize(options.root_dir.?.ptr, options.db_path.?.ptr, &err);
    if (handle_maybe) |handle| {
        @branchHint(.likely);
        self.handle = handle;
    } else {
        std.log.err("failed to initialize alpm library (root: {s}, dbpath: {s}): {s}", .{
            options.root_dir.?,
            options.db_path.?,
            c.alpm_strerror(err),
        });
        if (err == c.ALPM_ERR_DB_VERSION) {
            std.log.err("try running pacman-db-upgrade", .{});
        }
        return error.AlpmInitFailed;
    }
}

pub fn setLogFile(self: *Config) !void {
    const options = self.schema.options;
    try self.check(c.alpm_option_set_logfile(self.handle, options.log_file.?.ptr));
}

pub fn setGpgDir(self: *Config) !void {
    const options = self.schema.options;
    try self.check(c.alpm_option_set_gpgdir(self.handle, options.gpg_dir.?.ptr));
}

pub fn setCallbacks(self: *Config, ctx: *callbacks.Context) void {
    _ = c.alpm_option_set_logcb(self.handle, callbacks.cb_log, ctx);
    _ = c.alpm_option_set_dlcb(self.handle, callbacks.cb_download, ctx);
    _ = c.alpm_option_set_eventcb(self.handle, callbacks.cb_event, ctx);
    _ = c.alpm_option_set_questioncb(self.handle, callbacks.cb_question, ctx);
    _ = c.alpm_option_set_progresscb(self.handle, callbacks.cb_progress, ctx);
}

pub fn setHookDirs(self: *Config) !void {
    const options = self.schema.options;
    try self.check(c.alpm_option_add_hookdir(self.handle, options.hook_dir.?.ptr));
}

fn parseZonFromPath(comptime T: type, gpa: mem.Allocator, path: [:0]const u8) !T {
    var file = try std.fs.cwd().openFileZ(path, .{});
    defer file.close();

    const source = try file.readToEndAlloc(gpa, 8 * 4096);
    defer gpa.free(source);

    const source_cstr = try gpa.dupeZ(u8, source);
    defer gpa.free(source_cstr);

    var status: zon.parse.Status = .{};
    defer status.deinit(gpa);

    const data = try zon.parse.fromSlice(T, gpa, source_cstr, &status, .{});
    errdefer zon.parse.free(gpa, data);

    return data;
}

/// Helper method to check the return value of an ALPM C function call.
/// This replaces repetitive `if (ret != 0)` blocks.
fn check(self: *Config, ret: c_int) !void {
    if (ret != 0) {
        std.log.err("alpm configuration failed: {s}", .{c.alpm_strerror(c.alpm_errno(self.handle))});
        return error.AlpmConfigFailed;
    }
}

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const zon = std.zon;
const callbacks = @import("callbacks.zig");
const Config = @This();
