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
        var i: ?*c.alpm_list_t = self.sync_dbs;
        while (i) |n| : (i = c.alpm_list_next(i)) {
            const db: ?*c.alpm_db_t = @ptrCast(n.data);
            if (c.alpm_db_get_valid(db) != 0) {
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

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const zon = std.zon;
const posix = std.posix;
const assert = std.debug.assert;
const log = std.log;
const Pacman = @import("../Pacman.zig");
const utils = @import("../utils.zig");
const RemoteDatabases = @This();
