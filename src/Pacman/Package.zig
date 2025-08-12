pub const Map = std.StringHashMap(Package);

pub const Reason = enum(c_int) {
    explicit = 0,
    depend,
    unknown,
};

pub const Iterator = struct {
    list: ?*c.alpm_list_t,

    pub fn next(self: *Iterator) ?Package {
        const node = self.list orelse return null;
        self.list = c.alpm_list_next(self.list);
        return .{
            .pkg = @ptrCast(node.data.?),
        };
    }

    pub fn lookup(self: *Iterator, target: []const u8) ?Package {
        while (self.next()) |pkg| {
            if (mem.eql(u8, target, pkg.name())) {
                return pkg;
            }
        }
        return null;
    }
};

pkg: *c.alpm_pkg_t,

pub fn name(self: *const Package) []const u8 {
    return mem.span(self.nameC());
}

pub fn nameC(self: *const Package) [*c]const u8 {
    return c.alpm_pkg_get_name(self.pkg);
}

pub fn downloadSize(self: *const Package) usize {
    return @intCast(c.alpm_pkg_download_size(self.pkg));
}

pub fn installedSize(self: *const Package) usize {
    return @intCast(c.alpm_pkg_get_isize(self.pkg));
}

pub fn version(self: *const Package) []const u8 {
    return mem.span(c.alpm_pkg_get_version(self.pkg));
}

pub fn versionC(self: *const Package) [*c]const u8 {
    return c.alpm_pkg_get_version(self.pkg);
}

pub fn allocFormat(self: *const Package, gpa: mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(gpa, "{s}-{s}", .{
        self.name(),
        self.version(),
    });
}

pub const UnrequiredOption = struct {
    keep_optional: bool = true,
};

pub fn isUnrequired(self: *const Package, options: UnrequiredOption) bool {
    var requiredby = c.alpm_pkg_compute_requiredby(self.pkg);
    defer {
        c.alpm_list_free_inner(requiredby, c.free);
        c.alpm_list_free(requiredby);
    }
    if (requiredby == null) {
        if (options.keep_optional) {
            requiredby = c.alpm_pkg_compute_optionalfor(self.pkg);
        }
        if (requiredby == null) {
            return true;
        }
    }
    return false;
}

pub fn getReason(self: *const Package) Reason {
    return @enumFromInt(c.alpm_pkg_get_reason(self.pkg));
}

pub fn getUrlC(self: *const Package) [*c]const u8 {
    return c.alpm_pkg_get_url(self.pkg);
}

pub fn getUrl(self: *const Package) []const u8 {
    return mem.span(self.getUrlC());
}

pub fn getDescriptionC(self: *const Package) [*c]const u8 {
    return c.alpm_pkg_get_desc(self.pkg);
}

pub fn getDescription(self: *const Package) []const u8 {
    return mem.span(self.getDescriptionC());
}

pub fn getArchitectureC(self: *const Package) [*c]const u8 {
    return c.alpm_pkg_get_arch(self.pkg);
}

pub fn getArchitecture(self: *const Package) []const u8 {
    return mem.span(self.getArchitectureC());
}

pub fn getDepends(self: *const Package, gpa: mem.Allocator) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .init(gpa);
    defer list.deinit();

    var it: Depdendency.Iterator = .{
        .list = c.alpm_pkg_get_depends(self.pkg),
    };
    while (it.next()) |dep| try list.append(dep.name());

    return try list.toOwnedSlice();
}

pub fn getRepositoryC(self: *const Package) [*c]const u8 {
    return c.alpm_db_get_name(c.alpm_pkg_get_db(self.pkg));
}

pub fn getRepository(self: *const Package) []const u8 {
    return mem.span(self.getRepositoryC());
}

pub fn getLicenses(self: *const Package, gpa: mem.Allocator) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .init(gpa);
    defer list.deinit();
    var it: License.Iterator = .{
        .list = c.alpm_pkg_get_licenses(self.pkg),
    };
    while (it.next()) |license| try list.append(license.name());
    return try list.toOwnedSlice();
}

pub const Info = struct {
    repository: ?[]const u8 = null,
    name: []const u8,
    version: []const u8,
    depends_on: []const []const u8,
    description: []const u8,
    architecture: []const u8,
    url: []const u8,
    licenses: []const []const u8,

    pub fn print(self: Info) !void {
        const stdout_file = std.io.getStdOut().writer();
        var bw = std.io.bufferedWriter(stdout_file);
        const stdout = bw.writer();
        try zon.stringify.serialize(self, .{}, stdout);
        try stdout.writeByte('\n');
        try bw.flush();
    }

    pub fn deinit(self: *Info, gpa: mem.Allocator) void {
        gpa.free(self.depends_on);
        gpa.free(self.licenses);
    }
};

pub fn info(self: *const Package, gpa: mem.Allocator) !Info {
    return .{
        .repository = self.getRepository(),
        .name = self.name(),
        .version = self.version(),
        .depends_on = try self.getDepends(gpa),
        .description = self.getDescription(),
        .architecture = self.getArchitecture(),
        .url = self.getUrl(),
        .licenses = try self.getLicenses(gpa),
    };
}

const std = @import("std");
const c = @import("c");
const mem = std.mem;
const zon = std.zon;
const Depdendency = @import("Dependency.zig");
const License = @import("License.zig");
const Package = @This();
