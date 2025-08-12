ctx: *Pacman,
data: ?*c.alpm_list_t = null,
flags: c_int = 0,
explicit_adds: Package.Map,
explicit_removes: Package.Map,

pub fn DataIterator(comptime T: type) type {
    return struct {
        i: ?*c.alpm_list_t = null,

        pub fn next(self: *@This()) ?T {
            const node = self.i orelse return null;
            self.i = c.alpm_list_next(self.i);
            return @ptrCast(@alignCast(node.data.?));
        }
    };
}

pub fn init(ctx: *Pacman) Transaction {
    return .{
        .ctx = ctx,
        .explicit_adds = .init(ctx.gpa),
        .explicit_removes = .init(ctx.gpa),
    };
}

pub fn deinit(self: *Transaction) void {
    self.explicit_adds.deinit();
    self.explicit_removes.deinit();
    if (self.data) |d| c.alpm_list_free(d);
}

pub fn dataIterator(self: *Transaction, comptime T: type) DataIterator(T) {
    return .{ .i = self.data };
}

pub fn acquireLock(self: *Transaction) !void {
    if (c.alpm_trans_init(self.ctx.handle, self.flags) == -1) {
        return self.ctx.getError();
    }
}

pub fn releaseLock(self: *Transaction) void {
    _ = c.alpm_trans_release(self.ctx.handle);
}

pub fn sysupgrade(self: *Transaction) !void {
    utils.colonPrint("Starting full system upgrade...\n", .{});
    _ = c.alpm_logaction(
        self.ctx.handle,
        c.PACMAN_CALLER_PREFIX,
        "starting full system upgrade\n",
    );
    if (c.alpm_sync_sysupgrade(self.ctx.handle, 0) == -1) {
        return self.ctx.getError();
    }
}

pub fn prepare(self: *Transaction) !void {
    if (c.alpm_trans_prepare(self.ctx.handle, &self.data) == -1) {
        log.err("failed to prepare transaction ({s})", .{self.ctx.getErrorStr()});
        switch (self.ctx.getError()) {
            error.PackageInvalidArchError => {
                var pkg_it = self.dataIterator([*:0]u8);
                while (pkg_it.next()) |pkg| {
                    defer c.free(pkg);
                    utils.colonPrint(
                        "package {s} does not have a valid architecture\n",
                        .{pkg},
                    );
                }
            },
            error.UnsatisfiedDependenciesError => {
                var dep_it = self.dataIterator(*c.alpm_depmissing_t);
                while (dep_it.next()) |dep| {
                    defer c.alpm_depmissing_free(dep);
                    self.printBrokenDependency(dep);
                }
            },
            error.ConflictingDependenciesError => {
                var conflict_it = self.dataIterator(*c.alpm_conflict_t);
                while (conflict_it.next()) |conflict| {
                    defer c.alpm_conflict_free(conflict);
                    switch (conflict.reason.*.mod) {
                        c.ALPM_DEP_MOD_ANY => {
                            utils.colonPrint(
                                "{s}-{s} and {s}-{s} are in conflict\n",
                                .{
                                    c.alpm_pkg_get_name(conflict.package1),
                                    c.alpm_pkg_get_version(conflict.package1),
                                    c.alpm_pkg_get_name(conflict.package2),
                                    c.alpm_pkg_get_version(conflict.package2),
                                },
                            );
                        },
                        else => {
                            const reason = c.alpm_dep_compute_string(conflict.reason);
                            defer c.free(reason);
                            utils.colonPrint(
                                "{s}-{s} and {s}-{s} are in conflict ({s})\n",
                                .{
                                    c.alpm_pkg_get_name(conflict.package1),
                                    c.alpm_pkg_get_version(conflict.package1),
                                    c.alpm_pkg_get_name(conflict.package2),
                                    c.alpm_pkg_get_version(conflict.package2),
                                    reason,
                                },
                            );
                        },
                    }
                }
            },
            else => return error.UnexpectedError,
        }
    }
}

pub fn commit(self: *Transaction) !void {
    if (c.alpm_trans_get_add(self.ctx.handle)) |packages| {
        _ = packages;
    } else {
        utils.print(" there is nothing to do\n", .{});
        return;
    }

    try self.displayTargets();

    const confirm = c.yesno("Proceed with installation?");
    if (confirm <= 0) {
        return error.CancelledByUSer;
    }
    c.multibar_move_completed_up(true);
    if (c.alpm_trans_commit(self.ctx.handle, &self.data) == -1) {
        log.err("failed to commit transaction ({s})", .{self.ctx.getErrorStr()});
        switch (self.ctx.getError()) {
            error.FileConflictsError => {
                var conflict_it = self.dataIterator(*c.alpm_fileconflict_t);
                while (conflict_it.next()) |conflict| {
                    defer c.alpm_fileconflict_free(conflict);
                    switch (conflict.type) {
                        c.ALPM_FILECONFLICT_TARGET => {
                            log.err("{s} exists in both '{s}' and '{s}'", .{
                                conflict.file,
                                conflict.target,
                                conflict.ctarget,
                            });
                            break;
                        },
                        c.ALPM_FILECONFLICT_FILESYSTEM => {
                            if (conflict.ctarget[0] > 0) {
                                log.err("{s}: {s} exists in filesystem (owned by {s})", .{
                                    conflict.target,
                                    conflict.file,
                                    conflict.ctarget,
                                });
                            } else {
                                log.err("{s}: {s} exists in filesystem", .{
                                    conflict.target,
                                    conflict.file,
                                });
                            }
                        },
                        else => {},
                    }
                }
            },
            error.PackageInvalidError,
            error.PackageInvalidChecksumError,
            error.PackageInvalidSignatureError,
            => {
                var file_it = self.dataIterator([*:0]u8);
                while (file_it.next()) |file| {
                    defer c.free(file);
                    log.err("{s} is invalid or corrupted", .{file});
                }
            },
            else => {},
        }
        log.err("Errors occurred, no packages were upgraded.", .{});
    }
}

pub fn getAdds(self: *Transaction) Package.Iterator {
    return .{
        .list = c.alpm_trans_get_add(self.ctx.handle),
    };
}

pub fn getRemoves(self: *Transaction) Package.Iterator {
    return .{
        .list = c.alpm_trans_get_remove(self.ctx.handle),
    };
}

pub const TargetsInfo = struct {
    packages: []const []const u8 = &.{},
    total_download_size: ?usize = null,
    total_installed_size: ?usize = null,
    total_removed_size: ?usize = null,
    net_upgrade_size: ?usize = null,
};

pub fn displayTargets(self: *Transaction) !void {
    var arena: std.heap.ArenaAllocator = .init(self.ctx.gpa);
    defer arena.deinit();

    const gpa = arena.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var targets: std.ArrayList(Target) = .init(gpa);
    defer targets.deinit();

    const db_local = try LocalDatabase.init(self.ctx);

    var pkg_add_it = self.getAdds();
    while (pkg_add_it.next()) |pkg| {
        var target: Target = .{
            .install = pkg,
            .remove = db_local.packageLookup(pkg.name()),
        };
        if (self.explicit_adds.get(mem.span(pkg.name()))) |_| {
            target.is_explicit = true;
        }
        try targets.append(target);
    }

    var pkg_del_it = self.getRemoves();
    while (pkg_del_it.next()) |pkg| {
        var target: Target = .{
            .remove = db_local.packageLookup(pkg.name()),
        };
        if (self.explicit_removes.get(mem.span(pkg.name()))) |_| {
            target.is_explicit = true;
        }
        try targets.append(target);
    }

    var total_download_size: usize = 0;
    var total_installed_size: usize = 0;
    var total_removed_size: usize = 0;

    var packages: std.ArrayList([]const u8) = .init(gpa);
    defer packages.deinit();

    var targets_info: TargetsInfo = .{};
    for (targets.items) |target| {
        if (target.install) |pkg| {
            total_download_size += pkg.downloadSize();
            total_installed_size += pkg.installedSize();
        }
        if (target.remove) |pkg| {
            total_removed_size += pkg.installedSize();
        }
    }

    for (targets.items) |target| {
        if (target.install) |pkg| {
            const name = try pkg.allocFormat(gpa);
            try packages.append(name);
        } else if (total_installed_size == 0) {
            if (target.remove) |pkg| {
                const name = try pkg.allocFormat(gpa);
                try packages.append(name);
            }
        } else {
            if (target.remove) |pkg| {
                const name = try pkg.allocFormat(gpa);
                try packages.append(name);
            }
        }
    }

    if (total_download_size > 0) {
        targets_info.total_download_size = total_download_size;
    }

    if (total_installed_size > 0) {
        targets_info.total_installed_size = total_installed_size;
    }

    if (total_removed_size > 0 and total_installed_size == 0) {
        targets_info.total_removed_size = total_removed_size;
    }

    if (total_installed_size > 0 and total_removed_size > 0) {
        targets_info.net_upgrade_size = total_installed_size - total_removed_size;
    }

    targets_info.packages = packages.items;

    try zon.stringify.serialize(targets_info, .{}, stdout);
    try stdout.writeByte('\n');

    try bw.flush(); // Don't forget to flush!
}

fn printBrokenDependency(self: *Transaction, miss: *c.alpm_depmissing_t) void {
    const depstring = c.alpm_dep_compute_string(miss.depend);
    defer c.free(depstring);
    const trans_add = c.alpm_trans_get_add(self.ctx.handle);
    if (miss.causingpkg == null) {
        // package being installed/upgraded has unresolved dependency */
        utils.colonPrint("unable to satisfy dependency '{s}' required by {s}\n", .{
            depstring,
            miss.target,
        });
    } else if (c.alpm_pkg_find(trans_add, miss.causingpkg)) |pkg| {
        // upgrading a package breaks a local dependency */
        utils.colonPrint("installing {s} ({s}) breaks dependency '{s}' required by {s}\n", .{
            miss.causingpkg,
            c.alpm_pkg_get_version(pkg),
            depstring,
            miss.target,
        });
    } else {
        // removing a package breaks a local dependency */
        utils.colonPrint("removing {s} breaks dependency '{s}' required by {s}\n", .{
            miss.causingpkg,
            depstring,
            miss.target,
        });
    }
}

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const zon = std.zon;
const posix = std.posix;
const assert = std.debug.assert;
const Pacman = @import("../Pacman.zig");
const utils = @import("../utils.zig");
const log = std.log;
const Target = @import("Target.zig");
const Package = @import("Package.zig");
const LocalDatabase = @import("LocalDatabase.zig");
const Transaction = @This();
