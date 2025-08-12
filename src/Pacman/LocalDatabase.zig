db: *c.alpm_db_t,
ctx: *Pacman,

pub fn init(ctx: *Pacman) !LocalDatabase {
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

pub fn packageLookup(self: *const LocalDatabase, name: [*c]const u8) ?Package {
    const pkg = c.alpm_db_get_pkg(self.db, name) orelse
        return null;
    return .{
        .pkg = pkg,
    };
}

const std = @import("std");
const c = @import("c");
const Pacman = @import("../Pacman.zig");
const Package = @import("Package.zig");
const utils = Pacman.utils;
const LocalDatabase = @This();
