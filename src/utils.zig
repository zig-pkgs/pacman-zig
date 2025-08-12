pub const DumpData = struct {
    root: []const u8,
    db_path: []const u8,
    cache_dirs: []const []const u8 = &.{},
    hook_dirs: []const []const u8 = &.{},
    lock_file: []const u8,
    log_file: []const u8,
    gpg_dir: []const u8,
};

/// A Zig error set representing all possible failure conditions from the ALPM C library.
pub const AlpmError = error{
    // System Errors
    MemoryError,
    SystemError,
    PermissionDeniedError,
    NotAFileError,
    NotADirectoryError,
    WrongArgumentsError,
    DiskSpaceError,

    // Interface Errors
    HandleNotInitializedError,
    HandleAlreadyInitializedError,
    HandleLockError,

    // Database Errors
    DatabaseOpenError,
    DatabaseCreateError,
    DatabaseNotInitializedError,
    DatabaseAlreadyRegisteredError,
    DatabaseNotFoundError,
    DatabaseInvalidError,
    DatabaseInvalidSignatureError,
    DatabaseVersionError,
    DatabaseWriteError,
    DatabaseRemoveError,

    // Server Errors
    ServerInvalidUrlError,
    ServerNoneError,

    // Transaction Errors
    TransactionAlreadyInitializedError,
    TransactionNotInitializedError,
    TransactionDuplicateTargetError,
    TransactionDuplicateFilenameError,
    TransactionNotPreparedError,
    TransactionAbortedError,
    TransactionTypeError,
    TransactionNotLockedError,
    TransactionHookFailedError,

    // Package Errors
    PackageNotFoundError,
    PackageIgnoredError,
    PackageInvalidError,
    PackageInvalidChecksumError,
    PackageInvalidSignatureError,
    PackageMissingSignatureError,
    PackageOpenError,
    PackageCannotRemoveError,
    PackageInvalidNameError,
    PackageInvalidArchError,

    // Signature Errors
    SignatureMissingError,
    SignatureInvalidError,

    // Dependency Errors
    UnsatisfiedDependenciesError,
    ConflictingDependenciesError,
    FileConflictsError,

    // Miscellaneous Errors
    RetrieveError,
    InvalidRegexError,

    // External Library Errors
    LibarchiveError,
    LibcurlError,
    GpgmeError,
    ExternalDownloaderError,

    // Missing Compile-time Features
    MissingSignatureCapabilityError,

    // An unknown or unhandled error from the C library
    UnknownError,
};

// Assume you have access to the C header definitions at the top of your file:
// const c = @cImport(@cInclude("alpm.h"));

/// Converts a C `alpm_errno_t` value to a corresponding Zig `AlpmError`.
///
/// NOTE: This function assumes the input `err` is NOT 0 (ALPM_ERR_OK).
/// The caller is responsible for checking for success before calling this.
pub fn alpmErrnoToError(handle: *c.alpm_handle_t) AlpmError {
    const err = c.alpm_errno(handle);
    return switch (err) {
        c.ALPM_ERR_MEMORY => error.MemoryError,
        c.ALPM_ERR_SYSTEM => error.SystemError,
        c.ALPM_ERR_BADPERMS => error.PermissionDeniedError,
        c.ALPM_ERR_NOT_A_FILE => error.NotAFileError,
        c.ALPM_ERR_NOT_A_DIR => error.NotADirectoryError,
        c.ALPM_ERR_WRONG_ARGS => error.WrongArgumentsError,
        c.ALPM_ERR_DISK_SPACE => error.DiskSpaceError,

        c.ALPM_ERR_HANDLE_NULL => error.HandleNotInitializedError,
        c.ALPM_ERR_HANDLE_NOT_NULL => error.HandleAlreadyInitializedError,
        c.ALPM_ERR_HANDLE_LOCK => error.HandleLockError,

        c.ALPM_ERR_DB_OPEN => error.DatabaseOpenError,
        c.ALPM_ERR_DB_CREATE => error.DatabaseCreateError,
        c.ALPM_ERR_DB_NULL => error.DatabaseNotInitializedError,
        c.ALPM_ERR_DB_NOT_NULL => error.DatabaseAlreadyRegisteredError,
        c.ALPM_ERR_DB_NOT_FOUND => error.DatabaseNotFoundError,
        c.ALPM_ERR_DB_INVALID => error.DatabaseInvalidError,
        c.ALPM_ERR_DB_INVALID_SIG => error.DatabaseInvalidSignatureError,
        c.ALPM_ERR_DB_VERSION => error.DatabaseVersionError,
        c.ALPM_ERR_DB_WRITE => error.DatabaseWriteError,
        c.ALPM_ERR_DB_REMOVE => error.DatabaseRemoveError,

        c.ALPM_ERR_SERVER_BAD_URL => error.ServerInvalidUrlError,
        c.ALPM_ERR_SERVER_NONE => error.ServerNoneError,

        c.ALPM_ERR_TRANS_NOT_NULL => error.TransactionAlreadyInitializedError,
        c.ALPM_ERR_TRANS_NULL => error.TransactionNotInitializedError,
        c.ALPM_ERR_TRANS_DUP_TARGET => error.TransactionDuplicateTargetError,
        c.ALPM_ERR_TRANS_DUP_FILENAME => error.TransactionDuplicateFilenameError,
        c.ALPM_ERR_TRANS_NOT_PREPARED => error.TransactionNotPreparedError,
        c.ALPM_ERR_TRANS_ABORT => error.TransactionAbortedError,
        c.ALPM_ERR_TRANS_TYPE => error.TransactionTypeError,
        c.ALPM_ERR_TRANS_NOT_LOCKED => error.TransactionNotLockedError,
        c.ALPM_ERR_TRANS_HOOK_FAILED => error.TransactionHookFailedError,

        c.ALPM_ERR_PKG_NOT_FOUND => error.PackageNotFoundError,
        c.ALPM_ERR_PKG_IGNORED => error.PackageIgnoredError,
        c.ALPM_ERR_PKG_INVALID => error.PackageInvalidError,
        c.ALPM_ERR_PKG_INVALID_CHECKSUM => error.PackageInvalidChecksumError,
        c.ALPM_ERR_PKG_INVALID_SIG => error.PackageInvalidSignatureError,
        c.ALPM_ERR_PKG_MISSING_SIG => error.PackageMissingSignatureError,
        c.ALPM_ERR_PKG_OPEN => error.PackageOpenError,
        c.ALPM_ERR_PKG_CANT_REMOVE => error.PackageCannotRemoveError,
        c.ALPM_ERR_PKG_INVALID_NAME => error.PackageInvalidNameError,
        c.ALPM_ERR_PKG_INVALID_ARCH => error.PackageInvalidArchError,

        c.ALPM_ERR_SIG_MISSING => error.SignatureMissingError,
        c.ALPM_ERR_SIG_INVALID => error.SignatureInvalidError,

        c.ALPM_ERR_UNSATISFIED_DEPS => error.UnsatisfiedDependenciesError,
        c.ALPM_ERR_CONFLICTING_DEPS => error.ConflictingDependenciesError,
        c.ALPM_ERR_FILE_CONFLICTS => error.FileConflictsError,

        c.ALPM_ERR_RETRIEVE => error.RetrieveError,
        c.ALPM_ERR_INVALID_REGEX => error.InvalidRegexError,

        c.ALPM_ERR_LIBARCHIVE => error.LibarchiveError,
        c.ALPM_ERR_LIBCURL => error.LibcurlError,
        c.ALPM_ERR_GPGME => error.GpgmeError,
        c.ALPM_ERR_EXTERNAL_DOWNLOAD => error.ExternalDownloaderError,

        c.ALPM_ERR_MISSING_CAPABILITY_SIGNATURES => error.MissingSignatureCapabilityError,

        else => error.UnknownError,
    };
}

pub fn parseZonFromPath(comptime T: type, gpa: mem.Allocator, path: [:0]const u8) !T {
    var file = try std.fs.cwd().openFileZ(path, .{});
    defer file.close();

    const source = try file.readToEndAlloc(gpa, 8 * 4096);
    defer gpa.free(source);

    const source_cstr = try gpa.dupeZ(u8, source);
    defer gpa.free(source_cstr);

    var status: zon.parse.Status = .{};
    defer status.deinit(gpa);

    const data = try zon.parse.fromSlice(T, gpa, source_cstr, &status, .{});
    errdefer zon.parse.free(gpa, data);

    return data;
}

pub fn getuid() c_uint {
    return c.getuid();
}

pub fn colonPrint(comptime format: []const u8, args: anytype) void {
    _ = c.fputs(c.config.*.colstr.colon, c.stdout);
    print(format, args);
    _ = c.fputs(c.config.*.colstr.nocolor, c.stdout);
    _ = c.fflush(c.stdout);
}

pub fn print(comptime format: []const u8, args: anytype) void {
    if (format.len == 1) {
        const str: [:0]const u8 = &.{format[0]};
        _ = c.printf(str);
        return;
    }
    const buf = std.fmt.allocPrintZ(std.heap.c_allocator, format, args) catch return;
    defer std.heap.c_allocator.free(buf);
    _ = c.printf(buf);
}

pub fn flushStdout() void {
    _ = c.fflush(c.stdout);
}

pub const console = struct {
    // Moves console cursor `lines` up */
    pub fn cursorMoveUp(lines: usize) void {
        print("\x1B[{d}F", .{lines});
    }

    // Moves console cursor `lines` down */
    pub fn cursorMoveDown(lines: usize) void {
        print("\x1B[{d}E", .{lines});
    }

    pub fn cursorHide() void {
        if (std.io.getStdOut().isTty())
            print(CURSOR_HIDE_ANSICODE, .{});
    }

    pub fn cursorShow() void {
        if (std.io.getStdOut().isTty())
            print(CURSOR_SHOW_ANSICODE, .{});
    }
};

pub const Columns = struct {
    var cached: ?u16 = null;

    pub fn get() u16 {
        if (cached) |cache| return cache;

        const col = getFd(std.io.getStdOut().handle) catch 80;
        cached = col;
        return col;
    }

    pub fn resetCache() void {
        cached = null;
    }

    pub fn getFd(fd: posix.fd_t) !u16 {
        if (!posix.isatty(fd)) return error.NotTty;
        var winsz: posix.winsize = undefined;
        while (true) {
            const rc = linux.ioctl(
                fd,
                linux.T.IOCGWINSZ,
                @intFromPtr(&winsz),
            );
            switch (linux.E.init(rc)) {
                .SUCCESS => {
                    cached = winsz.ws_col;
                    return winsz.ws_col;
                },
                .INTR => continue,
                else => |e| return posix.unexpectedErrno(e),
            }
        }
    }
};

pub const SoftInterrupt = struct {
    var self_pipe_fds: [2]posix.fd_t = .{ -1, -1 };

    fn handler(signum: i32) callconv(.c) void {
        const bytes = mem.asBytes(&signum);
        var sum: usize = 0;
        while (sum < bytes.len) {
            const amt = posix.write(self_pipe_fds[1], bytes) catch continue;
            sum += amt;
        }
    }

    pub fn installHandler() !posix.fd_t {
        // 1. Create the pipe
        self_pipe_fds = try posix.pipe();

        // 2. Make the write end of the pipe non-blocking.
        // This ensures the write in the signal handler never blocks,
        // even in the unlikely event the pipe buffer is full.
        const flags = try posix.fcntl(self_pipe_fds[1], posix.F.GETFL, 0);
        _ = try posix.fcntl(self_pipe_fds[1], posix.F.SETFL, flags);

        // 3. Register the signal handler
        var newaction: posix.Sigaction = .{
            .handler = .{
                .handler = handler,
            },
            .flags = posix.SA.RESTART, // Restart syscalls if interrupted by this signal
            .mask = posix.empty_sigset,
        };
        _ = c.sigaddset(@ptrCast(&newaction.mask), posix.SIG.INT);
        _ = c.sigaddset(@ptrCast(&newaction.mask), posix.SIG.HUP);
        posix.sigaction(posix.SIG.INT, &newaction, null);
        posix.sigaction(posix.SIG.HUP, &newaction, null);

        // Return the read end of the pipe
        return self_pipe_fds[0];
    }

    pub fn removeHandler() void {
        resetHandler(posix.SIG.INT);
        resetHandler(posix.SIG.HUP);
        inline for (self_pipe_fds) |fd| posix.close(fd);
    }

    fn resetHandler(signum: u6) void {
        var newaction: posix.Sigaction = .{
            .handler = .{
                .handler = linux.SIG.DFL,
            },
            .flags = 0,
            .mask = posix.empty_sigset,
        };
        posix.sigaction(signum, &newaction, null);
    }
};

pub const WindowChange = struct {
    fn handler(signum: i32) callconv(.c) void {
        _ = signum;
        c.columns_cache_reset(); // TODO: replace with zig implementation
    }

    pub fn installHandler() void {
        var newaction: posix.Sigaction = .{
            .handler = .{
                .handler = handler,
            },
            .flags = posix.SA.RESTART, // Restart syscalls if interrupted by this signal
            .mask = posix.empty_sigset,
        };
        posix.sigaction(posix.SIG.WINCH, &newaction, null);
    }
};

pub fn handleSoftInterrupt(
    signal_fd: posix.fd_t,
    handle: *c.alpm_handle_t,
    gpa: mem.Allocator,
) !void {
    const signal_file: std.fs.File = .{ .handle = signal_fd };
    var poller = std.io.poll(gpa, enum { signal_fd }, .{ .signal_fd = signal_file });
    defer poller.deinit();
    while (try poller.poll()) {
        const bytes = poller.fifo(.signal_fd).readableSliceOfLen(@sizeOf(i32));
        const signum = mem.readInt(i32, bytes[0..4], native_endian);
        poller.fifo(.signal_fd).discard(bytes.len);
        c.console_cursor_move_end();
        if (signum == posix.SIG.INT) {
            const msg = "\nInterrupt signal received\n";
            print(msg, .{});
        } else {
            const msg = "\nHangup signal received\n";
            print(msg, .{});
        }
        print("{s}", .{CURSOR_SHOW_ANSICODE});
        if (c.alpm_trans_interrupt(handle) == 0) {
            continue;
        }
        _ = c.alpm_unlock(handle);
        print("\n", .{});
        return;
    }
}

pub const CURSOR_HIDE_ANSICODE = "\x1B[?25l";
pub const CURSOR_SHOW_ANSICODE = "\x1B[?25h";

const std = @import("std");
const c = @import("c");
const linux = std.os.linux;
const posix = std.posix;
const Pacman = @import("Pacman.zig");
const Config = Pacman.Config;
const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();
const mem = std.mem;
const zon = std.zon;
