pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    nosuspend {
        if (std.io.getStdErr().isTty()) {
            const prefix = switch (message_level) {
                inline .err => color_str.On.err,
                inline .warn => color_str.On.warn,
                inline else => "",
            };
            const suffix = switch (message_level) {
                inline .err, .warn => color_str.On.nocolor,
                inline else => "",
            };
            const level_txt = comptime prefix ++ message_level.asText() ++ suffix;
            writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
        } else {
            const prefix = switch (message_level) {
                inline .err => color_str.Off.err,
                inline .warn => color_str.Off.warn,
                inline else => "",
            };
            const suffix = switch (message_level) {
                inline .err, .warn => color_str.Off.nocolor,
                inline else => "",
            };
            const level_txt = comptime prefix ++ message_level.asText() ++ suffix;
            writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
        }

        bw.flush() catch return;
    }
}

pub fn logFormat(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) ![*c]u8 {
    if (!std.log.logEnabled(message_level, scope)) return null;

    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    var list: std.ArrayList(u8) = .init(std.heap.c_allocator);
    defer list.deinit();
    const writer = list.writer();

    nosuspend {
        if (std.io.getStdErr().isTty()) {
            const prefix = switch (message_level) {
                inline .err => color_str.On.err,
                inline .warn => color_str.On.warn,
                inline else => "",
            };
            const suffix = switch (message_level) {
                inline .err, .warn => color_str.On.nocolor,
                inline else => "",
            };
            const level_txt = comptime prefix ++ message_level.asText() ++ suffix;
            try writer.print(level_txt ++ prefix2 ++ format ++ "\n", args);
        } else {
            const prefix = switch (message_level) {
                inline .err => color_str.Off.err,
                inline .warn => color_str.Off.warn,
                inline else => "",
            };
            const suffix = switch (message_level) {
                inline .err, .warn => color_str.Off.nocolor,
                inline else => "",
            };
            const level_txt = comptime prefix ++ message_level.asText() ++ suffix;
            try writer.print(level_txt ++ prefix2 ++ format ++ "\n", args);
        }
    }
    return try list.toOwnedSliceSentinel('\x00');
}

const std = @import("std");
const color_str = @import("Config.zig").color_str;
