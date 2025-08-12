name_cstr: [*c]const u8,

pub const Iterator = struct {
    list: ?*c.alpm_list_t,

    pub fn next(self: *Iterator) ?License {
        const node = self.list orelse return null;
        self.list = c.alpm_list_next(self.list);
        return .{
            .name_cstr = @ptrCast(@alignCast(node.data.?)),
        };
    }
};

pub fn name(self: License) []const u8 {
    return mem.span(self.name_cstr);
}

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const Package = @import("Package.zig");
const License = @This();
