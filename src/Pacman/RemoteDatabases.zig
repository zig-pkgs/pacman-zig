sync_dbs: *c.alpm_list_t,
ctx: *Pacman,

pub fn init(ctx: *Pacman) !RemoteDatabases {
    const sync_dbs_maybe = c.alpm_get_syncdbs(ctx.handle);
    if (sync_dbs_maybe) |sync_dbs| {
        return .{
            .ctx = ctx,
            .sync_dbs = sync_dbs,
        };
    } else {
        return ctx.getError();
    }
}

pub fn iterator(self: *RemoteDatabases) Database.Iterator {
    return .{
        .ctx = self.ctx,
        .list = self.sync_dbs,
    };
}

pub const CheckOptions = struct {
    need_repos: bool = false,
    check_valid: bool = false,
};

pub fn check(self: *RemoteDatabases, options: CheckOptions) bool {
    if (options.need_repos) {
        log.err("no usable package repositories configured.", .{});
        return false;
    }
    if (options.check_valid) {
        var iter = self.iterator();
        while (iter.next()) |db| {
            if (!db.isValid()) {
                log.err("database '{s}' is not valid ({s})", .{
                    c.alpm_db_get_name(db),
                    self.ctx.getErrorStr(),
                });
                return false;
            }
        }
    }
    return true;
}

pub fn find(self: *RemoteDatabases, name: []const u8) ?Database {
    var it = self.iterator();
    while (it.next()) |db| {
        if (mem.eql(u8, db.getName(), name)) {
            return db;
        }
    }
    return null;
}

pub const SyncOptions = struct {
    force: bool = false,
};

pub fn sync(self: *RemoteDatabases, options: SyncOptions) !void {
    utils.colonPrint("Synchronizing package databases...\n", .{});
    _ = c.alpm_logaction(
        self.ctx.handle,
        c.PACMAN_CALLER_PREFIX,
        "synchronizing package lists\n",
    );
    c.multibar_move_completed_up(false);
    if (c.alpm_db_update(
        self.ctx.handle,
        self.sync_dbs,
        @intFromBool(options.force),
    ) < 0) {
        log.err(
            "failed to synchronize all databases ({s})",
            .{self.ctx.getErrorStr()},
        );
        return self.ctx.getError();
    }
}

pub fn findGroupPackages(self: *RemoteDatabases, name: [*:0]const u8) Package.Iterator {
    return .{
        .list = c.alpm_find_group_pkgs(self.sync_dbs, name),
    };
}

pub fn findSatisfier(self: *RemoteDatabases, name: [*:0]const u8) ?Package {
    return .{
        .pkg = c.alpm_find_dbs_satisfier(
            self.ctx.handle,
            self.sync_dbs,
            name,
        ) orelse return null,
    };
}

pub fn lookup(self: *RemoteDatabases, target: []const u8) ?Package {
    var it = self.iterator();
    while (it.next()) |db| {
        var pkg_cache = db.getPkgCache();
        if (pkg_cache.lookup(target)) |pkg| {
            return pkg;
        }
    }
    return null;
}

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const zon = std.zon;
const posix = std.posix;
const assert = std.debug.assert;
const log = std.log;
const Pacman = @import("../Pacman.zig");
const Database = @import("Database.zig");
const utils = @import("../utils.zig");
const Package = @import("Package.zig");
const RemoteDatabases = @This();
