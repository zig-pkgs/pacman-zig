pub const ProgressBar = struct {
    config: *c.config_t,
    filename: [:0]u8,
    xfered: c.off_t = 0,
    total_size: c.off_t = 0,
    downloaded: usize = 0,
    howmany: usize = 0,
    init_time: time.Instant,
    sync_time: time.Instant,
    sync_xfered: c.off_t = 0,
    rate: f64 = 0.0,
    eta: c_uint = 0,
    completed: bool = false,

    pub const List = std.ArrayList(ProgressBar);

    pub fn draw(self: ProgressBar) void {
        const file_percent: c_int = if (self.total_size > 0)
            @intCast(@divExact((self.sync_xfered * 100), self.total_size))
        else
            100;
        _ = file_percent;
    }
};

pub const MultibarUi = struct {
    active_downloads: ProgressBar.List,
    move_completed_up: bool = false,
    cursor_lineno: usize = 0,

    pub fn cursorGotoBar(self: *MultibarUi, num: usize) void {
        if (num > self.cursor_lineno) {
            utils.console.cursorMoveDown(num - self.cursor_lineno);
        } else if (num < self.cursor_lineno) {
            utils.console.cursorMoveUp(self.cursor_lineno - num);
        }
        self.cursor_lineno = num;
    }

    pub fn cursorMoveEnd(self: *MultibarUi) void {
        return self.cursorGotoBar(self.active_downloads.items.len);
    }
};

const gpa = std.heap.c_allocator;

var multibar_ui: MultibarUi = .{
    .active_downloads = .init(gpa),
};
var total_enabled: usize = 0;
var totalbar: ?ProgressBar = null;

fn cleanFilename(filename: []const u8) []const u8 {
    const index = mem.lastIndexOfScalar(u8, filename, '.') orelse
        return filename;
    if (index == 0) return filename[1..];
    return filename[0..index];
}

fn dload_init_event(config: *c.config_t, filename: []const u8, data: [*c]c.alpm_download_event_init_t) !void {
    _ = data;
    const cleaned_filename = cleanFilename(filename);
    if (c.dload_progressbar_enabled(config) == 0) {
        utils.print(" {s} downloading...\n", .{cleaned_filename});
        return;
    }
    const bar: ProgressBar = .{
        .config = config,
        .init_time = try time.Instant.now(),
        .sync_time = try time.Instant.now(),
        .filename = try gpa.dupeZ(u8, filename),
    };
    try multibar_ui.active_downloads.append(bar);

    multibar_ui.cursorMoveEnd();
    utils.print(" {s}\n", .{cleaned_filename});
    multibar_ui.cursor_lineno += 1;

    if (total_enabled > 0) {
        if (totalbar) |b| b.draw();
        utils.print("\n", .{});
        multibar_ui.cursor_lineno += 1;
    }
}

pub fn cb_download(
    ctx: ?*anyopaque,
    filename: [*c]const u8,
    event: c.alpm_download_event_type_t,
    data: ?*anyopaque,
) callconv(.c) void {
    std.debug.assert(ctx != null);
    const config: *c.config_t = @ptrCast(@alignCast(ctx.?));
    const filename_str = mem.span(filename);
    //defer c.free(@ptrCast(@constCast(filename)));

    // do not print signature files progress bar
    if (mem.endsWith(u8, filename_str, ".sig")) return;

    switch (event) {
        c.ALPM_DOWNLOAD_INIT => dload_init_event(config, filename_str, @ptrCast(@alignCast(data))) catch return,
        c.ALPM_DOWNLOAD_PROGRESS => c.dload_progress_event(config, filename, @ptrCast(@alignCast(data))),
        c.ALPM_DOWNLOAD_RETRY => c.dload_retry_event(config, filename, @ptrCast(@alignCast(data))),
        c.ALPM_DOWNLOAD_COMPLETED => c.dload_complete_event(config, filename, @ptrCast(@alignCast(data))),
        else => utils.colonPrint("unknown callback event type {d} for {s}\n", .{
            event,
            filename_str,
        }),
    }
}

pub fn cb_log(
    ctx: ?*anyopaque,
    level: c.alpm_loglevel_t,
    fmt: [*c]const u8,
    args: [*c]c.struct___va_list_tag_2,
) callconv(.c) void {
    _ = ctx;
    if (fmt == null and mem.len(fmt) == 0) {
        return;
    }

    var msg: [*c]u8 = null;
    if (c.vasprintf(&msg, fmt, args) <= 0) return;
    defer c.free(msg);
    const msg_s = mem.trimRight(u8, mem.span(msg), "\n");

    if (c.on_progress > 0) {
        var string: [*c]u8 = null;
        switch (level) {
            c.ALPM_LOG_ERROR => {
                string = logFormat(.err, .default, "{s}", .{msg_s}) catch return;
            },
            c.ALPM_LOG_WARNING => {
                string = logFormat(.warn, .default, "{s}", .{msg_s}) catch return;
            },
            c.ALPM_LOG_DEBUG => {
                string = logFormat(.debug, .default, "{s}", .{msg_s}) catch return;
            },
            c.ALPM_LOG_FUNCTION => {
                string = logFormat(.debug, .function, "{s}", .{msg_s}) catch return;
            },
            else => {
                string = logFormat(.debug, .default, "{s}", .{msg_s}) catch return;
            },
        }
        if (string) |s| c.output = c.alpm_list_add(c.output, @ptrCast(s));
    } else {
        switch (level) {
            c.ALPM_LOG_ERROR => {
                log.err("{s}", .{msg_s});
            },
            c.ALPM_LOG_WARNING => {
                log.warn("{s}", .{msg_s});
            },
            c.ALPM_LOG_DEBUG => {
                log.debug("{s}", .{msg_s});
            },
            c.ALPM_LOG_FUNCTION => {
                log.scoped(.function).debug("{s}", .{msg_s});
            },
            else => {
                log.debug("{s}", .{msg_s});
            },
        }
    }
}

const std = @import("std");
const mem = std.mem;
const log = std.log;
const time = std.time;
const Pacman = @import("../Pacman.zig");
const utils = Pacman.utils;
const logFormat = Pacman.log.logFormat;
const c = @import("c");
