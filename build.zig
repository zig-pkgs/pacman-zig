const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pacman_dep = b.dependency("pacman", .{});

    const config_h = b.addConfigHeader(.{
        .style = .{ .cmake = b.path("src/config.h.in") },
        .include_path = "config.h",
    }, .{
        .CACHEDIR = "/var/cache/pacman/pkg/",
        .CONFFILE = "/etc/pacman.conf",
        .DBPATH = "/var/lib/pacman/",
        .ENABLE_NLS = 1,
        .FSSTATSTYPE = .@"struct statvfs",
        .GPGDIR = "/etc/pacman.d/gnupg/",
        .HAVE_GETMNTENT = 1,
        .HAVE_LIBCURL = 1,
        .HAVE_LIBGPGME = 1,
        .HAVE_LIBSECCOMP = 1,
        .HAVE_LIBSSL = 1,
        .HAVE_LINUX_LANDLOCK_H = 1,
        .HAVE_MNTENT_H = 1,
        .HAVE_STRNDUP = 1,
        .HAVE_STRNLEN = 1,
        .HAVE_STRSEP = 1,
        .HAVE_STRUCT_STATFS_F_FLAGS = null,
        .HAVE_STRUCT_STATVFS_F_FLAG = 1,
        .HAVE_STRUCT_STAT_ST_BLKSIZE = 1,
        .HAVE_SWPRINTF = 1,
        .HAVE_SYS_MOUNT_H = 1,
        .HAVE_SYS_PARAM_H = 1,
        .HAVE_SYS_PRCTL_H = 1,
        .HAVE_SYS_STATVFS_H = 1,
        .HAVE_SYS_TYPES_H = 1,
        .HAVE_TCFLUSH = 1,
        .HAVE_TERMIOS_H = 1,
        .HOOKDIR = "/etc/pacman.d/hooks/",
        .LDCONFIG = "/usr/bin/ldconfig",
        .LIB_VERSION = "15.0.0",
        .LOCALEDIR = "/usr/share/locale",
        .LOGFILE = "/var/log/pacman.log",
        .PACKAGE = "pacman",
        .PACKAGE_VERSION = "7.0.0",
        .ROOTDIR = "/",
        .SCRIPTLET_SHELL = "/usr/bin/bash",
        .SYSHOOKDIR = "/usr/share/libalpm/hooks/",
    });

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(pacman_dep.path("src/common"));
    translate_c.addIncludePath(pacman_dep.path("src/pacman"));

    const lib_mod = b.addModule("pacman", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_mod.addConfigHeader(config_h);
    lib_mod.addImport("c", translate_c.createModule());
    lib_mod.linkSystemLibrary("alpm", .{});
    lib_mod.linkSystemLibrary("archive", .{});

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "pacman",
        .root_module = lib_mod,
    });
    lib.addCSourceFiles(.{
        .root = pacman_dep.path("src/common"),
        .files = &common_src,
        .flags = &.{
            "-std=gnu99",
            "-includeconfig.h",
        },
    });
    lib.addCSourceFiles(.{
        .root = pacman_dep.path("src/pacman"),
        .files = &pacman_src,
        .flags = &.{
            "-std=gnu99",
            "-includeconfig.h",
        },
    });
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

const common_src = [_][]const u8{
    "ini.c",
    "util-common.c",
};

const pacman_src = [_][]const u8{
    "check.c",
    "conf.c",
    "database.c",
    "deptest.c",
    "files.c",
    "package.c",
    "query.c",
    "remove.c",
    "sighandler.c",
    "sync.c",
    "callback.c",
    "upgrade.c",
    "util.c",
};
