db: *c.alpm_db_t,
ctx: *Pacman,

pub fn isValid(self: Database) bool {
    return c.alpm_db_get_valid(self.db) == 0;
}

pub fn getLocal(ctx: *Pacman) !Database {
    if (c.alpm_get_localdb(ctx.handle)) |db| {
        @branchHint(.likely);
        return .{
            .ctx = ctx,
            .db = db,
        };
    } else {
        return ctx.getError();
    }
}

pub const Iterator = struct {
    list: ?*c.alpm_list_t,
    ctx: *Pacman,

    pub fn next(self: *Iterator) ?Database {
        const node = self.list orelse return null;
        self.list = c.alpm_list_next(self.list);
        return .{
            .ctx = self.ctx,
            .db = @ptrCast(@alignCast(node.data)),
        };
    }
};

pub fn getUsage(self: Database) Repository.Usage {
    var usage: c_int = 0;
    _ = c.alpm_db_get_usage(self.db, &usage);
    return Repository.Usage.fromInt(usage);
}

pub fn setUsage(self: Database, usage: Repository.Usage) void {
    _ = c.alpm_db_set_usage(self.db, usage.toInt());
}

pub fn getName(self: Database) []const u8 {
    return mem.span(self.getNameC());
}

pub fn getNameC(self: Database) [*c]const u8 {
    return c.alpm_db_get_name(self.db);
}

pub fn packageLookup(self: *const Database, name: [*c]const u8) ?Package {
    const pkg = c.alpm_db_get_pkg(self.db, name) orelse
        return null;
    return .{
        .pkg = pkg,
    };
}

pub fn getGroup(self: *const Database, name: [*c]const u8) !Group {
    if (c.alpm_db_get_group(self.db, name)) |group| {
        return .{
            .group = group,
        };
    } else {
        return self.ctx.getError();
    }
}

pub fn getPkgCache(self: *const Database) Package.Iterator {
    return .{
        .list = c.alpm_db_get_pkgcache(self.db),
    };
}

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const Pacman = @import("../Pacman.zig");
const Package = @import("Package.zig");
const Config = @import("Config.zig");
const Repository = Config.Repository;
const Group = @import("Group.zig");
const Database = @This();
