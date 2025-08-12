const std = @import("std");
const c = @import("c");
const mem = std.mem;
const posix = std.posix;
const Config = @import("Config.zig");
const log = std.log.scoped(.ALPM);
const Pacman = @import("../Pacman.zig");

pub const ProgressBar = struct {
    pub fn init() ProgressBar {
        return .{};
    }
};

pub const Context = struct {
    gpa: mem.Allocator,
    // download progress bar */
    total_enabled: bool = false,
    list_total: c.off_t = 0.0,
    list_total_pkgs: usize = 0,
    totalbar: ProgressBar = .{},

    // delayed output during progress bar */
    on_progress: bool = false,
    output: std.ArrayList(u8),

    pub fn init(gpa: mem.Allocator) Context {
        return .{
            .gpa = gpa,
            .output = .init(gpa),
        };
    }

    pub fn deinit(self: *Context) void {
        self.output.deinit();
    }

    pub fn getPacman(self: *Context) *Pacman {
        return @fieldParentPtr("cb_ctx", self);
    }

    pub fn getConfig(self: *Context) *Config {
        const pacman: *Pacman = self.getPacman();
        return &pacman.config;
    }

    fn dloadProgressbarEnabled(self: *Context) bool {
        const config = self.getConfig();
        return !config.no_progressbar and c.getcols() > 0;
    }

    pub fn handleEvent(self: *Context, event: [*c]c.alpm_event_t) !void {
        const config = self.getConfig();
        switch (event.*.type) {
            c.ALPM_EVENT_HOOK_START => {
                if (event.*.hook.when == c.ALPM_HOOK_PRE_TRANSACTION) {
                    try stdout.print("Running pre-transaction hooks...\n", .{});
                } else {
                    try stdout.print("Running post-transaction hooks...\n", .{});
                }
            },
            c.ALPM_EVENT_HOOK_RUN_START => {
                const e = event.*.hook_run;
                try stdout.print("{d: >}/{d: >} {s}\n", .{ e.position, e.total, e.name });
            },
            c.ALPM_EVENT_CHECKDEPS_START => {
                try stdout.print("checking dependencies...\n", .{});
            },
            c.ALPM_EVENT_FILECONFLICTS_START => {
                if (config.no_progressbar) {
                    try stdout.print("checking for file conflicts...\n", .{});
                }
            },
            c.ALPM_EVENT_RESOLVEDEPS_START => {
                try stdout.print("looking for conflicting packages...\n", .{});
            },
            c.ALPM_EVENT_INTERCONFLICTS_START => {
                try stdout.print("resolving dependencies...\n", .{});
            },
            c.ALPM_EVENT_TRANSACTION_START => {
                try stdout.print("Processing package changes...", .{});
            },
            c.ALPM_EVENT_PACKAGE_OPERATION_START => {
                if (config.no_progressbar) {
                    const e = event.*.package_operation;
                    switch (e.operation) {
                        c.ALPM_PACKAGE_INSTALL => {
                            try stdout.print("installing {s}...\n", .{c.alpm_pkg_get_name(e.newpkg)});
                        },
                        c.ALPM_PACKAGE_UPGRADE => {
                            try stdout.print("upgrading {s}...\n", .{c.alpm_pkg_get_name(e.newpkg)});
                        },
                        c.ALPM_PACKAGE_REINSTALL => {
                            try stdout.print("reinstalling {s}...\n", .{c.alpm_pkg_get_name(e.newpkg)});
                        },
                        c.ALPM_PACKAGE_DOWNGRADE => {
                            try stdout.print("downgrading {s}...\n", .{c.alpm_pkg_get_name(e.newpkg)});
                        },
                        c.ALPM_PACKAGE_REMOVE => {
                            try stdout.print("removing {s}...\n", .{c.alpm_pkg_get_name(e.newpkg)});
                        },
                        else => unreachable,
                    }
                }
            },
            c.ALPM_EVENT_PACKAGE_OPERATION_DONE => {
                const e = event.*.package_operation;
                switch (e.operation) {
                    c.ALPM_PACKAGE_INSTALL => {},
                    c.ALPM_PACKAGE_UPGRADE,
                    c.ALPM_PACKAGE_DOWNGRADE,
                    => {},
                    c.ALPM_PACKAGE_REINSTALL,
                    c.ALPM_PACKAGE_REMOVE,
                    => {},
                    else => unreachable,
                }
            },
            c.ALPM_EVENT_INTEGRITY_START => {
                if (config.no_progressbar) {
                    try stdout.print("checking package integrity...\n", .{});
                }
            },
            c.ALPM_EVENT_KEYRING_START => {
                if (config.no_progressbar) {
                    try stdout.print("checking keyring...\n", .{});
                }
            },
            c.ALPM_EVENT_KEY_DOWNLOAD_START => {
                try stdout.print("downloading required keys...\n", .{});
            },
            c.ALPM_EVENT_LOAD_START => {
                if (config.no_progressbar) {
                    try stdout.print("loading package files...\n", .{});
                }
            },
            c.ALPM_EVENT_SCRIPTLET_INFO => {
                try stdout.print("{s}\n", .{event.*.scriptlet_info.line});
            },
            c.ALPM_EVENT_DB_RETRIEVE_START => self.on_progress = true,
            c.ALPM_EVENT_PKG_RETRIEVE_START => {
                try stdout.print("Retrieving packages...\n", .{});
                self.on_progress = true;
                self.list_total_pkgs = event.*.pkg_retrieve.num;
                self.list_total = event.*.pkg_retrieve.total_size;
                self.total_enabled = self.list_total > 0 and self.list_total_pkgs > 1 and
                    self.dloadProgressbarEnabled();

                if (self.total_enabled) {
                    self.totalbar = .init();
                }
                try stdout.print("checking keyring...\n", .{});
            },
            c.ALPM_EVENT_DISKSPACE_START => {
                if (config.no_progressbar) {
                    try stdout.print("checking available disk space...\n", .{});
                }
            },
            c.ALPM_EVENT_OPTDEP_REMOVAL => {
                const e = event.*.optdep_removal;
                const dep_string = c.alpm_dep_compute_string(e.optdep);
                defer c.free(dep_string);
                try stdout.print("{s} optionally requires {s}\n", .{ c.alpm_pkg_get_name(e.pkg), dep_string });
            },
            c.ALPM_EVENT_DATABASE_MISSING => {
                const pacman: *Pacman = self.getPacman();
                switch (pacman.operation) {
                    .sync => {},
                    else => {
                        log.warn(
                            "database file for '{s}' does not exist (use '{s}' to download)\n",
                            .{ event.*.database_missing.dbname, "-Fy" },
                        );
                    },
                }
            },
            c.ALPM_EVENT_PACNEW_CREATED => {
                const e = event.*.pacnew_created;
                if (self.on_progress) {
                    const string = try std.fmt.allocPrint(self.gpa, "{s} installed as {s}.pacnew\n", .{ e.file, e.file });
                    defer self.gpa.free(string);
                    try self.output.appendSlice(string);
                } else {
                    log.warn("{s} installed as {s}.pacnew\n", .{ e.file, e.file });
                }
            },
            c.ALPM_EVENT_PACSAVE_CREATED => {
                const e = event.*.pacsave_created;
                if (self.on_progress) {
                    const string = try std.fmt.allocPrint(self.gpa, "{s} saved as {s}.pacsave\n", .{ e.file, e.file });
                    defer self.gpa.free(string);
                    try self.output.appendSlice(string);
                } else {
                    log.warn("{s} saved as {s}.pacsave\n", .{ e.file, e.file });
                }
            },
            c.ALPM_EVENT_DB_RETRIEVE_DONE,
            c.ALPM_EVENT_DB_RETRIEVE_FAILED,
            c.ALPM_EVENT_PKG_RETRIEVE_DONE,
            c.ALPM_EVENT_PKG_RETRIEVE_FAILED,
            => {},
            c.ALPM_EVENT_FILECONFLICTS_DONE,
            c.ALPM_EVENT_CHECKDEPS_DONE,
            c.ALPM_EVENT_RESOLVEDEPS_DONE,
            c.ALPM_EVENT_INTERCONFLICTS_DONE,
            c.ALPM_EVENT_TRANSACTION_DONE,
            c.ALPM_EVENT_INTEGRITY_DONE,
            c.ALPM_EVENT_KEYRING_DONE,
            c.ALPM_EVENT_KEY_DOWNLOAD_DONE,
            c.ALPM_EVENT_LOAD_DONE,
            c.ALPM_EVENT_DISKSPACE_DONE,
            c.ALPM_EVENT_HOOK_DONE,
            c.ALPM_EVENT_HOOK_RUN_DONE,
            => {},
            else => unreachable,
        }
        try bw.flush();
    }

    pub fn handleQuestion(self: *Context, question: [*c]c.alpm_question_t) !void {
        const config = self.getConfig();
        switch (question.*.type) {
            c.ALPM_QUESTION_INSTALL_IGNOREPKG => {
                const q = &question.*.install_ignorepkg;
                if (config.sync.download_only) {
                    q.install = @intFromBool(true);
                }
            },
            c.ALPM_QUESTION_REPLACE_PKG => {},
            c.ALPM_QUESTION_CONFLICT_PKG => {},
            c.ALPM_QUESTION_REMOVE_PKGS => {},
            c.ALPM_QUESTION_SELECT_PROVIDER => {},
            c.ALPM_QUESTION_CORRUPTED_PKG => {},
            c.ALPM_QUESTION_IMPORT_KEY => {},
            else => unreachable,
        }
    }
};

const stdout_file = std.io.getStdOut().writer();
const stdin_file = std.io.getStdIn().writer();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

fn consoleEraseLine() void {
    stdout.print("\x1b[2K", .{}) catch {};
}

fn consoleCursorUp(lines: u32) void {
    if (lines == 0) return;
    stdout.writer().print("\x1b[{d}A", .{lines}) catch {};
}

fn consoleCursorDown(lines: u32) void {
    if (lines == 0) return;
    stdout.print("\x1b[{d}B", .{lines}) catch {};
}

fn yesOrNo(comptime format: []const u8, args: anytype) !bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    try stdout.print(format, args);
    try stdout.print(" [Y/n] ", .{});
    const line = try stdin_file.readUntilDelimiterOrEof(&buf, '\n');
    const answer = mem.trim(u8, line, "\t\n ");
    if (answer.len == 0) {
        return true;
    } else if (answer == 'Y' or answer == 'y') {
        return true;
    } else if (answer == 'N' or answer == 'n') {
        return false;
    } else {
        return false;
    }
}

pub fn cb_event(ctx: ?*anyopaque, event: [*c]c.alpm_event_t) callconv(.c) void {
    var cb_ctx: *Context = @ptrCast(@alignCast(ctx.?));
    cb_ctx.handleEvent(event) catch return;
}

pub fn cb_question(ctx: ?*anyopaque, question: [*c]c.alpm_question_t) callconv(.c) void {
    var cb_ctx: *Context = @ptrCast(@alignCast(ctx.?));
    cb_ctx.handleQuestion(question) catch return;
}

pub fn cb_progress(
    ctx: ?*anyopaque,
    event: c.alpm_progress_t,
    pkgname: [*c]const u8,
    percent: c_int,
    howmany: usize,
    remain: usize,
) callconv(.c) void {
    _ = ctx;
    _ = pkgname;
    _ = percent;
    _ = howmany;
    _ = remain;
    switch (event) {
        c.ALPM_PROGRESS_ADD_START => {},
        c.ALPM_PROGRESS_UPGRADE_START => {},
        c.ALPM_PROGRESS_DOWNGRADE_START => {},
        c.ALPM_PROGRESS_REINSTALL_START => {},
        c.ALPM_PROGRESS_REMOVE_START => {},
        c.ALPM_PROGRESS_CONFLICTS_START => {},
        c.ALPM_PROGRESS_DISKSPACE_START => {},
        c.ALPM_PROGRESS_INTEGRITY_START => {},
        c.ALPM_PROGRESS_KEYRING_START => {},
        c.ALPM_PROGRESS_LOAD_START => {},
        else => unreachable,
    }
}

pub fn cb_download(
    ctx: ?*anyopaque,
    filename: [*c]const u8,
    event: c.alpm_download_event_type_t,
    data: ?*anyopaque,
) callconv(.c) void {
    _ = ctx;
    _ = data;
    switch (event) {
        c.ALPM_DOWNLOAD_INIT => {},
        c.ALPM_DOWNLOAD_PROGRESS => {},
        c.ALPM_DOWNLOAD_RETRY => {},
        c.ALPM_DOWNLOAD_COMPLETED => {},
        else => log.err("unknown callback event type {d} for {s}", .{ event, filename }),
    }
}

pub fn cb_log(
    ctx: ?*anyopaque,
    level: c.alpm_loglevel_t,
    fmt: [*c]const u8,
    args: [*c]c.struct___va_list_tag_2,
) callconv(.c) void {
    const ap: *std.builtin.VaList = @ptrCast(args);

    const curr_ctx: *Context = @ptrCast(@alignCast(ctx.?));
    const format = mem.span(fmt);
    if (format.len == 0) return;

    var list: std.ArrayList(u8) = .init(curr_ctx.gpa);
    defer list.deinit();

    vformat(list.writer(), format, ap) catch return;

    if (curr_ctx.on_progress) {
        curr_ctx.output.appendSlice(list.items) catch return;
    } else {
        switch (level) {
            c.ALPM_LOG_ERROR => log.err("{s}", .{list.items}),
            c.ALPM_LOG_WARNING => log.warn("{s}", .{list.items}),
            c.ALPM_LOG_DEBUG => log.debug("{s}", .{list.items}),
            else => log.info("{s}", .{list.items}),
        }
    }
}

/// Formats a C-style format string with a C va_list, writing the result to a writer.
/// This function manually parses the format string and extracts arguments.
///
/// Parameters:
/// - writer: The std.io.Writer to write the formatted output to.
/// - fmt: A null-terminated C format string (e.g., "found %d packages for %s").
/// - ap: A pointer to a Zig VaList (`*std.builtin.VaList`).
///
/// Returns:
/// An error if writing to the writer fails (e.g., allocation error).
fn vformat(
    writer: anytype,
    fmt: []const u8,
    ap: *std.builtin.VaList,
) !void {
    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        if (fmt[i] != '%') {
            try writer.writeByte(fmt[i]);
            continue;
        }

        // We found a '%', so check the next character for the specifier.
        i += 1;

        switch (fmt[i]) {
            '%' => {
                // Escaped '%%', print a single '%'.
                try writer.writeByte('%');
            },
            's' => {
                // string argument
                const arg = @cVaArg(ap, [*:0]const u8);
                const slice = mem.sliceTo(arg, 0);
                try writer.print("{s}", .{slice});
            },
            'd' => {
                // integer argument
                const arg = @cVaArg(ap, c_int);
                try writer.print("{d}", .{arg});
            },
            'p' => {
                // pointer argument
                const arg = @cVaArg(ap, ?*anyopaque);
                try writer.print("0x{x}", .{@intFromPtr(arg)});
            },
            // Add other format specifiers as needed (e.g., 'u', 'x', 'c').
            // 'u' => {
            //     const arg = @cVaArg(ap, c_uint);
            //     try writer.print("{d}", .{arg});
            // },
            else => {
                // Unsupported format specifier. Print it literally for debugging.
                try writer.print("%{c}", .{fmt[i]});
            },
        }
    }
}
