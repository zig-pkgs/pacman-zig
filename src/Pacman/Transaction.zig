ctx: *Pacman,
data: ?*c.alpm_list_t = null,
flags: c_int = 0,
explicit_adds: Package.Map,
explicit_removes: Package.Map,

pub const Flags = packed struct(c_int) {
    // Ignore dependency checks.
    nodeps: bool = false,
    // (1 << 1) flag can go here
    _p1: bool = false,
    // Delete files even if they are tagged as backup.
    nosave: bool = false,
    // Ignore version numbers when checking dependencies.
    nodepversion: bool = false,
    // Remove also any packages depending on a package being removed.
    cascade: bool = false,
    // Remove packages and their unneeded deps (not explicitly installed).
    recurse: bool = true,
    // Modify database but do not commit changes to the filesystem.
    dbonly: bool = false,
    // Do not run hooks during a transaction
    nohooks: bool = false,
    // Use ALPM_PKG_REASON_DEPEND when installing packages.
    alldeps: bool = false,
    // Only download packages and do not actually install.
    downloadonly: bool = false,
    // Do not execute install scriptlets after installing.
    noscriptlet: bool = false,
    // Ignore dependency conflicts.
    noconflicts: bool = false,
    // (1 << 12) flag can go here
    _p2: bool = false, // 1 << 1 (reserved)
    // Do not install a package if it is already installed and up to date.
    needed: bool = true,
    // Use ALPM_PKG_REASON_EXPLICIT when installing packages.
    allexplicit: bool = false,
    // Do not remove a package if it is needed by another one.
    unneeded: bool = true,
    // Remove also explicitly installed unneeded deps (use with ALPM_TRANS_FLAG_RECURSE).
    recurseall: bool = false,
    // Do not lock the database during the operation.
    nolock: bool = false,
    padding: u14 = 0,
};

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

pub fn init(ctx: *Pacman, flags: Flags) Transaction {
    return .{
        .ctx = ctx,
        .flags = @bitCast(flags),
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
            error.PackageInvalidArchError => self.handleInvalidArch(),
            error.UnsatisfiedDependenciesError => self.handleUnsatisfiedDependencies(),
            error.ConflictingDependenciesError => self.handleConflictingDependencies(),
            else => return error.UnexpectedError,
        }
    }
}

fn handleInvalidArch(self: *Transaction) void {
    var pkg_it = self.dataIterator([*:0]u8);
    while (pkg_it.next()) |pkg| {
        defer c.free(pkg);
        utils.colonPrint(
            "package {s} does not have a valid architecture\n",
            .{pkg},
        );
    }
}

fn handleUnsatisfiedDependencies(self: *Transaction) void {
    var dep_it = self.dataIterator(*c.alpm_depmissing_t);
    while (dep_it.next()) |dep| {
        defer c.alpm_depmissing_free(dep);
        self.printBrokenDependency(dep);
    }
}

fn handleConflictingDependencies(self: *Transaction) void {
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
}

pub const ProcessTargetOptions = struct {
    operation: enum {
        add,
        del,
    },
    name: []const u8,
};

pub fn processTarget(self: *Transaction, options: ProcessTargetOptions) !void {
    switch (options.operation) {
        .add => try self.processAdd(options.name),
        .del => try self.processDel(options.name),
    }
}

pub fn processDel(self: *Transaction, name: []const u8) !void {
    const name_cstr = try self.ctx.gpa.dupeZ(u8, name);
    defer self.ctx.gpa.free(name_cstr);

    const local_db = try Database.getLocal(self.ctx);
    if (local_db.packageLookup(name_cstr)) |pkg| {
        try self.processDelPackage(pkg);
    } else {
        var group = try local_db.getGroup(name_cstr);
        var it = group.packageIterator();
        while (it.next()) |pkg| {
            try self.processDelPackage(pkg);
        }
    }
}

pub fn processAdd(self: *Transaction, name: []const u8) !void {
    var syncdbs = try RemoteDatabases.init(self.ctx);

    const name_cstr = try self.ctx.gpa.dupeZ(u8, name);
    defer self.ctx.gpa.free(name_cstr);

    if (syncdbs.findSatisfier(name_cstr)) |pkg| {
        try self.processAddPackage(pkg);
    } else {
        switch (self.ctx.getError()) {
            error.PackageIgnoredError => {
                // skip ignored packages when user says no */
                log.warn("skipping target: {s}\n", .{name});
                return;
            },
            else => {
                var it_pkg = syncdbs.findGroupPackages(name_cstr);
                while (it_pkg.next()) |group_pkg| {
                    try self.processAddPackage(group_pkg);
                }
            },
        }
    }
}

fn processAddPackage(self: *Transaction, pkg: Package) !void {
    if (c.alpm_add_pkg(self.ctx.handle, pkg.pkg) != 0) {
        return self.ctx.getError();
    }
    try self.explicit_adds.put(pkg.name(), pkg);
}

fn processDelPackage(self: *Transaction, pkg: Package) !void {
    if (c.alpm_remove_pkg(self.ctx.handle, pkg.pkg) != 0) {
        return self.ctx.getError();
    }
    try self.explicit_removes.put(pkg.name(), pkg);
}

pub fn commit(self: *Transaction) !void {
    const pkg_num = try self.displayTargets();
    if (pkg_num == 0) {
        utils.print(" there is nothing to do\n", .{});
        return;
    }

    if (c.alpm_trans_commit(self.ctx.handle, &self.data) == -1) {
        log.err("failed to commit transaction ({s})", .{self.ctx.getErrorStr()});
        switch (self.ctx.getError()) {
            error.FileConflictsError => self.handleFileConflicts(),
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
            else => |e| return e,
        }
    }
}

fn handleFileConflicts(self: *Transaction) void {
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

pub fn displayTargets(self: *Transaction) !usize {
    var arena: std.heap.ArenaAllocator = .init(self.ctx.gpa);
    defer arena.deinit();

    const gpa = arena.allocator();

    var file = try std.fs.cwd().createFile(
        "/etc/pacman/last_transaction.zon",
        .{ .truncate = true },
    );
    defer file.close();

    var bw = std.io.bufferedWriter(file.writer());
    const stdout = bw.writer();

    var targets: std.ArrayList(Target) = .init(gpa);
    defer targets.deinit();

    const db_local = try Database.getLocal(self.ctx);

    var pkg_add_it = self.getAdds();
    while (pkg_add_it.next()) |pkg| {
        var target: Target = .{
            .install = pkg,
            .remove = db_local.packageLookup(pkg.nameC()),
        };
        if (self.explicit_adds.get(pkg.name())) |_| {
            target.is_explicit = true;
        }
        try targets.append(target);
    }

    var pkg_del_it = self.getRemoves();
    while (pkg_del_it.next()) |pkg| {
        var target: Target = .{
            .remove = db_local.packageLookup(pkg.nameC()),
        };
        if (self.explicit_removes.get(pkg.name())) |_| {
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
        if (total_installed_size > total_removed_size) {
            targets_info.net_upgrade_size = total_installed_size - total_removed_size;
        }
    }

    targets_info.packages = packages.items;

    try zon.stringify.serialize(targets_info, .{}, stdout);
    try stdout.writeByte('\n');

    try bw.flush(); // Don't forget to flush!
    return packages.items.len;
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
const Database = @import("Database.zig");
const RemoteDatabases = @import("RemoteDatabases.zig");
const Transaction = @This();
