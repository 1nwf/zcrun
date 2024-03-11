const std = @import("std");
const linux = std.os.linux;
const utils = @import("utils.zig");

const CGROUP_PATH = "/sys/fs/cgroup/";
const Resource = enum {
    cpu,
    memory,
    pids,

    fn max(self: Resource) []const u8 {
        return switch (self) {
            inline else => |v| @tagName(v) ++ ".max",
        };
    }
};

/// container id
cid: []const u8,
allocator: std.mem.Allocator,

const Cgroup = @This();

pub fn init(cid: []const u8, allocator: std.mem.Allocator) !Cgroup {
    var cgroups = Cgroup{
        .cid = cid,
        .allocator = allocator,
    };
    try cgroups.initDirs();
    return cgroups;
}

fn initDirs(self: *Cgroup) !void {
    const path = try std.mem.concat(self.allocator, u8, &.{ CGROUP_PATH ++ "zcrun/", self.cid });
    defer self.allocator.free(path);
    const root_dir = path[0 .. std.mem.lastIndexOfScalar(u8, path, '/') orelse @panic("")];
    const skip_setup = !(try utils.createDirIfNotExists(root_dir));
    _ = try utils.createDirIfNotExists(path);
    if (skip_setup) return;

    // setup root cgroup
    const root_cgroup = try std.mem.concat(self.allocator, u8, &.{ root_dir, "/", "cgroup.subtree_control" });
    defer self.allocator.free(root_cgroup);
    var root_cgroup_file = try std.fs.openFileAbsolute(root_cgroup, .{ .mode = .write_only });
    defer root_cgroup_file.close();
    _ = try root_cgroup_file.write("+cpu +memory +pids"); // enable cpu, mem, and pid controllers in the root cgroup

}

pub fn setResourceMax(self: *Cgroup, resource: Resource, limit: []const u8) !void {
    const path = try std.mem.concat(self.allocator, u8, &.{ CGROUP_PATH, "zcrun/", self.cid, "/", resource.max() });
    defer self.allocator.free(path);
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
    defer file.close();
    std.debug.assert(try file.write(limit) == limit.len);
}

pub fn enterCgroup(self: *Cgroup) !void {
    const cgroup_path = try std.mem.concat(self.allocator, u8, &.{ CGROUP_PATH, "zcrun/", self.cid, "/cgroup.procs" });
    defer self.allocator.free(cgroup_path);
    const pid = linux.getpid();
    const file = try std.fs.openFileAbsolute(cgroup_path, .{ .mode = .write_only });
    defer file.close();
    try file.writer().print("{}", .{pid});
}
