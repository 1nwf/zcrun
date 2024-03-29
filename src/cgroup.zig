const std = @import("std");
const linux = std.os.linux;
const utils = @import("utils.zig");
const ResourceArgs = @import("args.zig").Resources;

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
options: ResourceArgs,
allocator: std.mem.Allocator,

const Cgroup = @This();

pub fn init(cid: []const u8, options: ResourceArgs, allocator: std.mem.Allocator) !Cgroup {
    var cgroups = Cgroup{
        .cid = cid,
        .options = options,
        .allocator = allocator,
    };
    try cgroups.initDirs();
    try cgroups.applyResourceLimits();
    return cgroups;
}

fn applyResourceLimits(self: *Cgroup) !void {
    if (self.options.mem) |val| {
        try self.setResourceMax(.memory, val);
    }

    if (self.options.cpu) |val| {
        try self.setResourceMax(.cpu, val);
    }

    if (self.options.pids) |val| {
        try self.setResourceMax(.pids, val);
    }
}

fn initDirs(self: *Cgroup) !void {
    const path = try std.mem.concat(self.allocator, u8, &.{ utils.CGROUP_PATH ++ "zcrun/", self.cid });
    defer self.allocator.free(path);
    _ = try utils.createDirIfNotExists(path);
}

pub fn setResourceMax(self: *Cgroup, resource: Resource, limit: []const u8) !void {
    const path = try std.mem.concat(self.allocator, u8, &.{ utils.CGROUP_PATH, "zcrun/", self.cid, "/", resource.max() });
    defer self.allocator.free(path);
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
    defer file.close();
    std.debug.assert(try file.write(limit) == limit.len);
}

pub fn enterCgroup(self: *Cgroup, pid: linux.pid_t) !void {
    const cgroup_path = try std.mem.concat(self.allocator, u8, &.{ utils.CGROUP_PATH, "zcrun/", self.cid, "/cgroup.procs" });
    defer self.allocator.free(cgroup_path);
    const file = try std.fs.openFileAbsolute(cgroup_path, .{ .mode = .write_only });
    defer file.close();
    try file.writer().print("{}", .{pid});
}

pub fn deinit(self: *Cgroup) !void {
    const path = try std.mem.concat(self.allocator, u8, &.{ utils.CGROUP_PATH ++ "zcrun/", self.cid });
    defer self.allocator.free(path);
    try std.fs.deleteDirAbsolute(path);
}
