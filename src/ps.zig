const std = @import("std");
const utils = @import("utils.zig");

pub const ContainerInfo = struct {
    name: []const u8,
    cmd: []const u8,

    pub fn print(self: ContainerInfo, writer: anytype) !void {
        try writer.print("{s}: {s}\n", .{ self.name, self.cmd });
    }
};

pub fn runningContainers(allocator: std.mem.Allocator) ![]ContainerInfo {
    const cgroup_path = utils.CGROUP_PATH ++ "zcrun/";
    var info = std.ArrayList(ContainerInfo).init(allocator);
    errdefer info.deinit();

    var cgroup_dir = try std.fs.openDirAbsolute(cgroup_path, .{ .iterate = true });
    defer cgroup_dir.close();

    var iter = cgroup_dir.iterate();

    while (try iter.next()) |val| {
        if (val.kind != .directory) continue;
        const c = (try getContainerInfo(allocator, val.name)) orelse continue;
        try info.append(c);
    }

    return info.toOwnedSlice();
}

fn getContainerInfo(allocator: std.mem.Allocator, name: []const u8) !?ContainerInfo {
    const procs_path = try std.mem.concat(allocator, u8, &.{ utils.CGROUP_PATH, "zcrun/", name, "/cgroup.procs" });
    defer allocator.free(procs_path);

    const procs_file = try std.fs.openFileAbsolute(procs_path, .{});
    defer procs_file.close();

    const procs = try procs_file.reader().readAllAlloc(allocator, std.math.maxInt(u8));
    var iter = std.mem.splitBackwardsScalar(u8, procs, '\n');
    _ = iter.next(); // skip empty line
    const running_proc = iter.next() orelse return null;

    const proc_exe = try std.mem.concat(allocator, u8, &.{ "/proc/", running_proc, "/exe" });
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    // TODO: strip container rootfs path from cmd
    const cmd = try std.fs.readLinkAbsolute(proc_exe, &buffer);
    var cmd_name = try allocator.alloc(u8, cmd.len);
    @memcpy(cmd_name[0..cmd.len], cmd);

    return .{
        .name = name,
        .cmd = cmd_name,
    };
}
