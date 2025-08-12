pub const SigLevel = @import("Config/SigLevel.zig");
pub const Options = @import("Config/Options.zig");
pub const Repository = @import("Config/Repository.zig");
pub const color_str = @import("Config/color_str.zig");

arena: ArenaAllocator,
options: Options,
repositories: []Repository,
inner: c.config_t = .{
    .op = c.PM_OP_MAIN,
    .logmask = c.ALPM_LOG_ERROR | c.ALPM_LOG_WARNING,
    .parallel_downloads = 1,
},

pub fn init(gpa: mem.Allocator, base_dir: []const u8) !Config {
    const config_file_path = try std.fs.path.joinZ(gpa, &.{ base_dir, "options.zon" });
    defer gpa.free(config_file_path);
    const repo_file_path = try std.fs.path.joinZ(gpa, &.{ base_dir, "repositories.zon" });
    defer gpa.free(repo_file_path);
    return .{
        .arena = .init(gpa),
        .options = try .parse(gpa, config_file_path),
        .repositories = try utils.parseZonFromPath([]Repository, gpa, repo_file_path),
    };
}

pub fn deinit(self: *Config) void {
    const gpa = self.getParent().gpa;
    self.arena.deinit();
    _ = c.alpm_release(self.getParent().handle);
    self.options.deinit(gpa);
}

pub fn getParent(self: *Config) *Pacman {
    return @fieldParentPtr("config", self);
}

pub fn translate(self: *Config) void {
    switch (self.options.color.?) {
        inline else => |t| {
            self.inner.colstr = @field(color_str, @tagName(t));
        },
    }
    self.inner.chomp = 1; // I love candy
    self.inner.color = self.options.color.?.toInt();
    self.inner.parallel_downloads = @intCast(self.options.parallel_downloads);

    if (c.alpm_capabilities() & c.ALPM_CAPABILITY_SIGNATURES > 0) {
        self.inner.localfilesiglevel = c.ALPM_SIG_USE_DEFAULT;
        self.inner.remotefilesiglevel = c.ALPM_SIG_USE_DEFAULT;
    }

    self.inner.cleanmethod = self.options.clean_method.toInt();

    if (std.io.getStdOut().isTty()) {
        utils.WindowChange.installHandler();
    } else {
        self.inner.noprogressbar = 1;
    }
}

pub fn initAlpmHandle(self: *Config) !void {
    var err: c.alpm_errno_t = 0;
    const pacman = self.getParent();
    const handle_maybe = c.alpm_initialize(self.options.rootdir.?, self.options.dbpath.?, &err);
    if (handle_maybe) |handle| {
        @branchHint(.likely);
        pacman.handle = handle;
        self.inner.handle = pacman.handle;
    } else {
        return pacman.getError();
    }
}

pub fn initAlpm(self: *Config) !void {
    try self.initAlpmHandle();

    const handle = self.getParent().handle;

    if (self.inner.op == c.PM_OP_FILES) {
        _ = c.alpm_option_set_dbext(handle, ".files");
    }

    try self.setAlpmOptions(.logfile);

    // Set GnuPG's home directory. This is not relative to rootdir, even if
    // rootdir is defined. Reasoning: gpgdir contains configuration data.
    try self.setAlpmOptions(.gpgdir);

    // Set user hook directory. This is not relative to rootdir, even if
    // rootdir is defined. Reasoning: hookdir contains configuration data.
    // add hook directories 1-by-1 to avoid overwriting the system directory
    try self.setAlpmOptions(.hookdirs);
    try self.setAlpmOptions(.cachedirs);
    try self.setAlpmOptions(.overwrite_files);
    try self.setAlpmOptions(.default_siglevel);
    try self.setAlpmOptions(.local_file_siglevel);
    try self.setAlpmOptions(.remote_file_siglevel);

    for (self.repositories) |*repository| try repository.register(self);
    self.freeRepositories();

    if ((c.alpm_capabilities() & c.ALPM_CAPABILITY_DOWNLOADER) <= 0) {
        log.err("no '{s}' configured", .{"XferCommand"});
        return error.XferCommandNeeded;
    }

    try self.setAlpmOptions(.architectures);
    try self.setAlpmOptions(.checkspace);
    try self.setAlpmOptions(.usesyslog);
    try self.setAlpmOptions(.sandboxuser);
    try self.setAlpmOptions(.disable_sandbox);
    try self.setAlpmOptions(.ignorepkgs);
    try self.setAlpmOptions(.ignoregroups);
    try self.setAlpmOptions(.noupgrades);
    try self.setAlpmOptions(.noextracts);
    try self.setAlpmOptions(.disable_dl_timeout);
    try self.setAlpmOptions(.parallel_downloads);
}

pub fn setCallbacks(self: *Config) void {
    const handle = self.getParent().handle;
    const ctx = &self.inner;
    c.config = ctx;
    _ = c.alpm_option_set_logcb(handle, callbacks.cb_log, ctx);
    _ = c.alpm_option_set_dlcb(handle, c.cb_download, ctx);
    _ = c.alpm_option_set_eventcb(handle, c.cb_event, ctx);
    _ = c.alpm_option_set_questioncb(handle, c.cb_question, ctx);
    _ = c.alpm_option_set_progresscb(handle, c.cb_progress, ctx);
}

pub fn setAlpmOptions(self: *Config, comptime option: @Type(.enum_literal)) !void {
    var ret: c_int = 0;
    const option_name = @tagName(option);
    const option_value = @field(self.options, option_name);
    const get_option_name = "alpm_option_get_" ++ option_name;
    const SetFn = @field(c, "alpm_option_set_" ++ option_name);
    const add_single_option = "alpm_option_add_" ++ option_name[0 .. option_name.len - 1];
    const params = @typeInfo(@TypeOf(SetFn)).@"fn".params;
    if (params.len == 2) {
        if (params[1].type) |ArgType| {
            switch (@typeInfo(ArgType)) {
                .int => {
                    switch (@typeInfo(@TypeOf(option_value))) {
                        .bool => {
                            ret = SetFn(self.getParent().handle, @intFromBool(option_value));
                        },
                        .int => {
                            ret = SetFn(self.getParent().handle, @intCast(option_value));
                        },
                        else => {
                            ret = SetFn(self.getParent().handle, option_value.toInt());
                        },
                    }
                },
                else => {
                    if (ArgType == [*c]const u8) {
                        ret = SetFn(self.getParent().handle, @ptrCast(option_value));
                    } else if (ArgType == [*c]c.alpm_list_t) {
                        const AddFn = @field(c, add_single_option);
                        const GetFn = @field(c, get_option_name);
                        const gpa = self.arena.allocator();
                        if (@typeInfo(@TypeOf(option_value)) == .@"enum") {
                            var list: AlpmList([*:0]u8) = .{ .gpa = gpa };
                            try list.add(try option_value.toString(gpa));
                            ret = SetFn(self.getParent().handle, list.list);
                            return try self.check(ret);
                        }
                        const old = GetFn(self.getParent().handle);
                        if (old == null) {
                            var list: AlpmList([*:0]u8) = .{ .gpa = gpa };
                            if (option_value) |value| {
                                for (value) |item| try list.add(item);
                            }
                            ret = SetFn(self.getParent().handle, list.list);
                        } else {
                            if (option_value) |value| {
                                for (value) |item| {
                                    ret = AddFn(self.getParent().handle, @ptrCast(item));
                                }
                            }
                        }
                    } else {
                        @compileError("Unsupported type");
                    }
                },
            }
        } else {
            @compileError("Unknown option type");
        }
    } else {
        @compileError("SetFn does not have second argument");
    }
    return try self.check(ret);
}

pub fn dumpConfig(self: *Config) !void {
    const gpa = self.getParent().gpa;
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const handle = self.getParent().handle;
    var data: utils.DumpData = .{
        .root = mem.span(c.alpm_option_get_root(handle)),
        .db_path = mem.span(c.alpm_option_get_dbpath(handle)),
        .lock_file = mem.span(c.alpm_option_get_lockfile(handle)),
        .log_file = mem.span(c.alpm_option_get_logfile(handle)),
        .gpg_dir = mem.span(c.alpm_option_get_gpgdir(handle)),
    };

    var cache_dirs: std.ArrayList([]u8) = .init(gpa);
    defer cache_dirs.deinit();
    var hook_dirs: std.ArrayList([]u8) = .init(gpa);
    defer hook_dirs.deinit();

    {
        defer data.cache_dirs = cache_dirs.items;
        var j: ?*c.alpm_list_t = c.alpm_option_get_cachedirs(handle);
        while (j) |d| : (j = c.alpm_list_next(j)) {
            const str: [*:0]u8 = @ptrCast(d.data.?);
            try cache_dirs.append(mem.span(str));
        }
    }
    {
        defer data.hook_dirs = hook_dirs.items;
        var j: ?*c.alpm_list_t = c.alpm_option_get_hookdirs(handle);
        while (j) |d| : (j = c.alpm_list_next(j)) {
            const str: [*:0]u8 = @ptrCast(d.data.?);
            try hook_dirs.append(mem.span(str));
        }
    }
    try zon.stringify.serialize(data, .{}, stdout);
    try stdout.writeByte('\n');

    try bw.flush(); // Don't forget to flush!
}

pub fn check(self: *Config, ret: c_int) !void {
    if (ret == 0) return;
    return self.getParent().getError();
}

fn freeRepositories(self: *Config) void {
    const gpa = self.getParent().gpa;
    zon.parse.free(gpa, self.repositories);
}

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const zon = std.zon;
const posix = std.posix;
const log = std.log.scoped(.config);
const assert = std.debug.assert;
const Pacman = @import("../Pacman.zig");
const callbacks = @import("callbacks.zig");
const AlpmList = Pacman.AlpmList;
const utils = Pacman.utils;
const ArenaAllocator = std.heap.ArenaAllocator;
const Config = @This();
