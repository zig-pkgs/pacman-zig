dep: *c.alpm_depend_t,

pub const Iterator = struct {
    list: ?*c.alpm_list_t,

    pub fn next(self: *Iterator) ?Dependency {
        const node = self.list orelse return null;
        self.list = c.alpm_list_next(self.list);
        return .{
            .dep = @ptrCast(@alignCast(node.data.?)),
        };
    }
};

pub fn nameC(self: Dependency) [*c]const u8 {
    return self.dep.name;
}

pub fn name(self: Dependency) []const u8 {
    return mem.span(self.nameC());
}

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const Package = @import("Package.zig");
const Dependency = @This();
