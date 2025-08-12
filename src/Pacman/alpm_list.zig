pub fn AlpmList(comptime T: type) type {
    return struct {
        gpa: mem.Allocator,
        list: ?*c.alpm_list_t = null,

        pub fn add(self: *@This(), data: T) !void {
            try self.appendInternal(@ptrCast(data));
        }

        // It's good practice for the name 'append' to signify adding to the end.
        pub fn append(self: *@This(), data: T) !void {
            std.debug.assert(self.list != null);
            try self.appendInternal(@ptrCast(data));
        }

        fn appendInternal(self: *@This(), data: *anyopaque) !void {
            var new_node = try self.gpa.create(c.alpm_list_t);
            new_node.data = data;
            new_node.next = null;
            // new_node.prev will be set below.

            if (self.list) |head| {
                // List exists: find the end and link the new node.
                const last = c.alpm_list_last(head);
                last.*.next = new_node;
                new_node.prev = last;
                // The head (self.list) remains unchanged.
            } else {
                // List is empty: the new node becomes the head.
                new_node.prev = null;
                self.list = new_node;
            }
        }
    };
}

const std = @import("std");
const mem = std.mem;
const c = @import("c");
