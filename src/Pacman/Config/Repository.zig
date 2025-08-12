name: [:0]const u8,
servers: []const [:0]const u8,
cached_servers: ?[]const [:0]const u8 = null,
siglevel: ?SigLevel = null,
usage: Usage = .all,

pub const Usage = enum {
    sync,
    search,
    install,
    upgrade,
    all,

    pub fn toInt(self: Usage) c_int {
        return switch (self) {
            .sync => c.ALPM_DB_USAGE_SYNC,
            .search => c.ALPM_DB_USAGE_SEARCH,
            .install => c.ALPM_DB_USAGE_INSTALL,
            .upgrade => c.ALPM_DB_USAGE_UPGRADE,
            .all => c.ALPM_DB_USAGE_ALL,
        };
    }

    pub fn fromInt(usage: c_int) Usage {
        return switch (usage) {
            c.ALPM_DB_USAGE_SYNC => .sync,
            c.ALPM_DB_USAGE_SEARCH => .search,
            c.ALPM_DB_USAGE_INSTALL => .install,
            c.ALPM_DB_USAGE_UPGRADE => .upgrade,
            c.ALPM_DB_USAGE_ALL => .all,
            else => unreachable,
        };
    }
};

pub fn register(self: *Repository, config: *Config) !void {
    const pacman = config.getParent();
    const gpa = pacman.gpa;
    const handle = pacman.handle;

    if (self.siglevel == null) {
        self.siglevel = config.options.default_siglevel;
    }

    const db_maybe = c.alpm_register_syncdb(handle, self.name, self.siglevel.?.toInt());
    if (db_maybe) |db| {
        try config.check(c.alpm_db_set_usage(db, self.usage.toInt()));
        if (self.cached_servers) |cached_servers| {
            for (cached_servers) |server| {
                try config.check(c.alpm_db_add_cache_server(db, server));
            }
        }
        const arch = try config.options.architectures.toSlice(gpa);
        defer gpa.free(arch);
        for (self.servers) |server| {
            var list: std.ArrayList(u8) = .init(gpa);
            defer list.deinit();
            if (mem.eql(u8, arch, "aarch64")) {
                if (server[server.len - 1] == '/') {
                    try list.writer().print("{s}{s}/{s}", .{ server, arch, self.name });
                } else {
                    try list.writer().print("{s}/{s}/{s}", .{ server, arch, self.name });
                }
            } else {
                if (server[server.len - 1] == '/') {
                    try list.writer().print("{s}{s}/os/{s}", .{ server, self.name, arch });
                } else {
                    try list.writer().print("{s}/{s}/os/{s}", .{ server, self.name, arch });
                }
            }
            const url = try list.toOwnedSliceSentinel('\x00');
            defer gpa.free(url);
            try config.check(c.alpm_db_add_server(db, url));
        }
    } else {
        return pacman.getError();
    }
}

const std = @import("std");
const mem = std.mem;
const c = @import("c");
const assert = std.debug.assert;
const SigLevel = @import("SigLevel.zig");
const Config = @import("../Config.zig");
const Options = @import("Options.zig");
const utils = @import("../../utils.zig");
const Architecture = Options.Architecture;
const Repository = @This();
