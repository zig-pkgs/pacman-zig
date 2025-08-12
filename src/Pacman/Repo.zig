/// Represents a repository configuration defined in the config file.
name: []const u8,
servers: std.ArrayListUnmanaged([]const u8) = .{},
cache_servers: std.ArrayListUnmanaged([]const u8) = .{},
siglevel: c_int = c.ALPM_SIG_USE_DEFAULT,
siglevel_mask: c_int = 0,
usage: c_int = c.ALPM_DB_USAGE_ALL,

/// Merges the global signature level with the repo-specific one.
pub fn mergeSigLevel(self: *Repo, global_siglevel: c_int) void {
    self.siglevel = if (self.siglevel_mask > 0)
        (self.siglevel & self.siglevel_mask) | (global_siglevel & ~self.siglevel_mask)
    else
        self.siglevel;
}

const std = @import("std");
const c = @import("c");
const builtin = @import("builtin");
const mem = std.mem;
const fs = std.fs;
const testing = std.testing;

const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const Repo = @This();
