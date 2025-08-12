group: *c.alpm_group_t,

pub fn packageIterator(self: *Group) Package.Iterator {
    return .{
        .list = self.group.packages,
    };
}

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const Package = @import("Package.zig");
const Group = @This();
