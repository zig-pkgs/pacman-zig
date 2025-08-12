const cli = .{
    .name = "ark",
    .description = "A declarative package keeper for Arch Linux, powered by alpm",
    .flags = .{
        .{
            .short = 'v',
            .long = "verbose",
            .description = "Show verbose logging",
        },
    },

    .subcommands = .{
        .{
            .name = "add",
            .description = "Add or modify constraints in WORLD and commit changes",
            .positionals = .{
                .{
                    .meta = .CONSTRAINTS,
                    .type = "string",
                    .description = "A list of constrains to be added to WORLD",
                    .capacity = 64,
                },
            },
        },
        .{
            .name = "del",
            .description = "Remove constraints from WORLD and commit changes",
            .positionals = .{
                .{
                    .meta = .CONSTRAINTS,
                    .type = "string",
                    .description = "A list of constrains to be removed from WORLD",
                    .capacity = 64,
                },
            },
        },
        .{
            .name = "fix",
            .description = "Fix, reinstall or upgrade packages without modifying WORLD",
        },
        .{
            .name = "update",
            .description = "Update repository indexes",
        },
        .{
            .name = "upgrade",
            .description = "Install upgrades available from repositories",
        },
        .{
            .name = "cache",
            .description = "Manage the local package cache",
        },
        .{
            .name = "info",
            .description = "Give detailed information about packages",
            .positionals = .{
                .{
                    .meta = .CONSTRAINTS,
                    .type = "string",
                    .description = "A list of constrains to be added to WORLD",
                    .capacity = 64,
                },
            },
        },
    },
};

const stderr_file = std.io.getStdErr().writer();

pub const std_options: std.Options = .{
    .logFn = Pacman.log.logFn,
};

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();

    const gpa = gpa_state.allocator();

    var arg_str_iter = try std.process.argsWithAllocator(gpa);
    defer arg_str_iter.deinit();

    const Args = argzon.Args(cli, .{});
    const args = try Args.parse(gpa, &arg_str_iter, stderr_file, .{});

    var pacman: Pacman = try .init(gpa);
    defer pacman.deinit();

    pacman.setCallbacks();

    if (args.flags.verbose) try pacman.config.dumpConfig();

    if (args.subcommands_opt) |sub_cmds| {
        switch (sub_cmds) {
            .add => |opt| {
                if (utils.getuid() > 0) return needsRoot();

                var transaction = try pacman.transaction(.{});
                defer transaction.deinit();

                try transaction.acquireLock();
                defer transaction.releaseLock();

                for (opt.positionals.CONSTRAINTS.slice()) |target| {
                    try transaction.processTarget(.{
                        .name = target,
                        .operation = .add,
                    });
                }
                try transaction.prepare();
                try transaction.commit();
            },
            .del => |opt| {
                if (utils.getuid() > 0) return needsRoot();

                var transaction = try pacman.transaction(.{});
                defer transaction.deinit();

                try transaction.acquireLock();
                defer transaction.releaseLock();

                for (opt.positionals.CONSTRAINTS.slice()) |target| {
                    try transaction.processTarget(.{
                        .name = target,
                        .operation = .del,
                    });
                }
                try transaction.prepare();
                try transaction.commit();
            },
            .update => {
                if (utils.getuid() > 0) return needsRoot();
                var remote_dbs = try pacman.remoteDatabases();
                try remote_dbs.sync(.{ .force = true });
            },
            .upgrade => {
                if (utils.getuid() > 0) return needsRoot();

                var transaction = try pacman.transaction(.{});
                defer transaction.deinit();

                try transaction.acquireLock();
                defer transaction.releaseLock();

                try transaction.sysupgrade();
                try transaction.prepare();
                try transaction.commit();
            },
            .cache => {
                if (utils.getuid() > 0) return needsRoot();
            },
            .fix => {
                if (utils.getuid() > 0) return needsRoot();

                var transaction = try pacman.transaction(.{});
                defer transaction.deinit();

                try transaction.acquireLock();
                defer transaction.releaseLock();

                var local_db = try pacman.getLocalDb();
                var it = local_db.getPkgCache();
                while (it.next()) |pkg| {
                    if (!pkg.isUnrequired(.{})) {
                        continue;
                    }
                    if (pkg.getReason() != .depend) {
                        continue;
                    }
                    try transaction.processDel(pkg.name());
                }
                try transaction.prepare();
                try transaction.commit();
            },
            .info => |opt| {
                var syncdbs = try pacman.remoteDatabases();
                for (opt.positionals.CONSTRAINTS.slice()) |target| {
                    if (syncdbs.lookup(target)) |pkg| {
                        var info = try pkg.info(gpa);
                        defer info.deinit(gpa);
                        try info.print();
                    }
                }
            },
        }
    } else {
        try Args.writeUsage(stderr_file);
    }
}

fn needsRoot() error{NeedsRoot} {
    log.err("you cannot perform this operation unless you are root.", .{});
    return error.NeedsRoot;
}

const std = @import("std");
const log = std.log;
const zon = std.zon;
const utils = Pacman.utils;
const argzon = @import("argzon");
const Pacman = @import("Pacman");
const Transaction = Pacman.Transaction;
