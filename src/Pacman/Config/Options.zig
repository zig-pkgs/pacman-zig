rootdir: ?[:0]u8 = null,
dbpath: ?[:0]u8 = null,
cachedirs: ?[]const [:0]u8 = null,
logfile: ?[:0]u8 = null,
gpgdir: ?[:0]u8 = null,
hookdirs: ?[]const [:0]u8 = null,
clean_method: CleanMethod = .keep_installed,
parallel_downloads: usize = 1,
disable_sandbox: bool = false,
color: ?Color = null,
sandboxuser: ?[:0]u8 = null,
usesyslog: bool = false,
overwrite_files: ?[]const [:0]u8 = null,
ignorepkgs: ?[]const [:0]u8 = null,
ignoregroups: ?[]const [:0]u8 = null,
noupgrades: ?[]const [:0]u8 = null,
noextracts: ?[]const [:0]u8 = null,
hold_packages: ?[]const [:0]const u8 = null,
disable_dl_timeout: bool = false,
architectures: Architecture = .auto,
checkspace: bool = true,
default_siglevel: SigLevel = .{},
local_file_siglevel: SigLevel = .{},
remote_file_siglevel: SigLevel = .{},

pub fn parse(gpa: mem.Allocator, config_path: [:0]const u8) !Options {
    var options = try utils.parseZonFromPath(Options, gpa, config_path);
    try options.setDefaults(gpa);
    return options;
}

pub fn deinit(self: *Options, gpa: mem.Allocator) void {
    zon.parse.free(gpa, self.*);
}

fn setDefaults(self: *Options, gpa: mem.Allocator) !void {
    if (self.color == null) {
        self.color = if (std.io.getStdOut().isTty()) .on else .off;
    }
    if (self.rootdir) |root_dir| {
        if (self.dbpath == null) {
            self.dbpath = try std.fs.path.joinZ(gpa, &.{
                root_dir,
                c.DBPATH,
            });
        }
        if (self.logfile == null) {
            self.logfile = try std.fs.path.joinZ(gpa, &.{
                root_dir,
                c.LOGFILE,
            });
        }
    } else {
        self.rootdir = try gpa.dupeZ(u8, c.ROOTDIR);
        if (self.dbpath == null) {
            self.dbpath = try gpa.dupeZ(u8, c.DBPATH);
        }
        if (self.logfile == null) {
            self.logfile = try gpa.dupeZ(u8, c.LOGFILE);
        }
    }
    if (self.gpgdir == null) {
        self.gpgdir = try gpa.dupeZ(u8, c.GPGDIR);
    }
    if (self.cachedirs == null) {
        const item = try gpa.dupeZ(u8, c.CACHEDIR);
        self.cachedirs = try gpa.dupe([:0]u8, &.{item});
    }
    if (self.hookdirs == null) {
        const item = try gpa.dupeZ(u8, c.HOOKDIR);
        self.hookdirs = try gpa.dupe([:0]u8, &.{item});
    }
    if (self.sandboxuser == null) {
        self.sandboxuser = try gpa.dupeZ(u8, "alpm");
    }
}

pub const CleanMethod = enum {
    keep_installed,
    keep_current,

    pub fn toInt(self: CleanMethod) c_ushort {
        return switch (self) {
            .keep_installed => c.PM_CLEAN_KEEPINST,
            .keep_current => c.PM_CLEAN_KEEPCUR,
        };
    }
};

pub const Architecture = enum {
    auto,
    x86_64,
    aarch64,

    pub fn toString(self: Architecture, gpa: mem.Allocator) ![:0]u8 {
        switch (self) {
            .auto => {
                const uts = posix.uname();
                return try gpa.dupeZ(u8, &uts.machine);
            },
            else => |t| {
                return try gpa.dupeZ(u8, @tagName(t));
            },
        }
    }

    pub fn toSlice(self: Architecture, gpa: mem.Allocator) ![]u8 {
        switch (self) {
            .auto => {
                const uts = posix.uname();
                return try gpa.dupe(u8, &uts.machine);
            },
            else => |t| {
                return try gpa.dupe(u8, @tagName(t));
            },
        }
    }
};

pub const Color = enum {
    off,
    on,

    pub fn toInt(self: Color) c_ushort {
        return switch (self) {
            .on => c.PM_COLOR_ON,
            .off => c.PM_COLOR_OFF,
        };
    }
};

const std = @import("std");
const mem = std.mem;
const zon = std.zon;
const c = @import("c");
const posix = std.posix;
const assert = std.debug.assert;
const SigLevel = @import("SigLevel.zig");
const utils = @import("../../utils.zig");
const Options = @This();
