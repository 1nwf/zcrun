const std = @import("std");

inline fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// zcrun run <name> <rootfs_path> <cmd>
const RunArgs = struct {
    name: []const u8,
    rootfs_path: []const u8,
    cmd: []const u8,

    pub fn parse(iter: *std.process.ArgIterator) !RunArgs {
        return .{
            .name = iter.next() orelse return error.MissingName,
            .rootfs_path = iter.next() orelse return error.MissingRootfs,
            .cmd = iter.next() orelse return error.MissingCmd,
        };
    }
};

pub const Args = union(enum) {
    run: RunArgs,
    ps,
    help,
};

pub const help =
    \\zcrun: linux container runtime
    \\
    \\arguments:
    \\run <name> <rootfs_path> <cmd>
    \\ps
    \\help
    \\
;

pub fn parseArgs(allocator: std.mem.Allocator) !Args {
    var cli_args = try std.process.argsWithAllocator(allocator);
    _ = cli_args.next(); // skip first arg
    const cmd = cli_args.next() orelse return error.InvalidArgs;

    inline for (std.meta.fields(Args)) |f| {
        if (f.type != void and !@hasDecl(f.type, "parse")) @compileError("must define parse fn");
        if (eql(cmd, f.name)) {
            if (f.type == void) {
                return @unionInit(Args, f.name, {});
            } else {
                return @unionInit(Args, f.name, try f.type.parse(&cli_args));
            }
        }
    }

    return error.InvalidArgs;
}
