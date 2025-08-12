pub const Map = std.StringHashMap(Package);

pub const Iterator = struct {
    list: ?*c.alpm_list_t,

    pub fn next(self: *Iterator) ?Package {
        const node = self.list orelse return null;
        self.list = c.alpm_list_next(self.list);
        return .{
            .pkg = @ptrCast(node.data.?),
        };
    }
};

pkg: *c.alpm_pkg_t,

pub fn name(self: *const Package) [*c]const u8 {
    return c.alpm_pkg_get_name(self.pkg);
}

pub fn downloadSize(self: *const Package) usize {
    return @intCast(c.alpm_pkg_download_size(self.pkg));
}

pub fn installedSize(self: *const Package) usize {
    return @intCast(c.alpm_pkg_get_isize(self.pkg));
}

pub fn version(self: *const Package) [*c]const u8 {
    return c.alpm_pkg_get_version(self.pkg);
}

pub fn allocFormat(self: *const Package, gpa: mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(gpa, "{s}-{s}", .{
        self.name(),
        self.version(),
    });
}

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const Package = @This();
