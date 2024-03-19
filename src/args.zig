const std = @import("std");

inline fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// zcrun run <name> <rootfs_path> <cmd>
pub const RunArgs = struct {
    name: []const u8,
    rootfs_path: []const u8,
    cmd: []const u8,
    resources: Resources,

    fn parse(args: *std.process.ArgIterator) !RunArgs {
        return .{
            .name = args.next() orelse return error.MissingName,
            .rootfs_path = args.next() orelse return error.MissingRootfs,
            .cmd = args.next() orelse return error.MissingCmd,
            .resources = try Resources.parse(args),
        };
    }
};

pub const Resources = struct {
    mem: ?[]const u8 = null,
    cpu: ?[]const u8 = null,
    pids: ?[]const u8 = null,
    fn parse(args: *std.process.ArgIterator) !Resources {
        var r = Resources{};
        while (args.next()) |arg| {
            inline for (comptime std.meta.fieldNames(Resources)) |field| {
                // options can be passed as "-m [val]" or "-mem [val]"
                if (eql(arg, "-" ++ field[0..1]) or eql(arg, "-" ++ field)) {
                    @field(r, field) = args.next() orelse return error.MissingValue;
                }
            }
        }
        return r;
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
