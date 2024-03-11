const std = @import("std");

inline fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// zcrun run <rootfs_path> <cmd>
const RunArgs = struct {
    rootfs_path: []const u8,
    cmd: []const u8,

    pub fn parse(iter: *std.process.ArgIterator) !RunArgs {
        return .{
            .rootfs_path = iter.next() orelse return error.MissingRootfs,
            .cmd = iter.next() orelse return error.MissingCmd,
        };
    }
};

pub const Args = union(enum) {
    run: RunArgs,
    help,
};

pub const help =
    \\zcrun: linux container runtime
    \\
    \\arguments:
    \\run <rootfs_path> <cmd>
;

pub fn parseArgs(allocator: std.mem.Allocator) !Args {
    var cli_args = try std.process.argsWithAllocator(allocator);
    var args: ?Args = null;
    _ = cli_args.next(); // skip first arg
    const cmd = cli_args.next() orelse return error.InvalidArgs;

    if (eql(cmd, "run")) {
        args = .{ .run = try RunArgs.parse(&cli_args) };
    } else if (eql(cmd, "help")) {
        args = .help;
    }

    return args orelse return error.InvalidArgs;
}
