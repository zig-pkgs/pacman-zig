install: ?Package = null,
remove: ?Package = null,
is_explicit: bool = false,

const Package = @import("Package.zig");
const Target = @This();
