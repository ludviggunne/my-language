const std = @import("std");

pub fn build(b: *std.Build) void {

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "lc",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const fmt = b.addExecutable(.{
        .name = "lfmt",
        .root_source_file = .{ .path = "src/fmt.zig" },
        .target = target,
        .optimize = optimize,
    });

    const install_root = b.addInstallArtifact(
        exe,
        .{
            .dest_dir = .{ .override = .{ .custom = "../", }, },
        }
    );

    const install_fmt = b.addInstallArtifact(
        fmt,
        .{
            .dest_dir = .{ .override = .{ .custom = "../", }, },
        }
    );

    b.getInstallStep().dependOn(&install_root.step);
    b.getInstallStep().dependOn(&install_fmt.step);
}
