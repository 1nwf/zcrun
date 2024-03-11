const std = @import("std");
const log = std.log;
const linux = std.os.linux;
const Net = @import("net.zig");
const Cgroup = @import("cgroup.zig");
const checkErr = @import("utils.zig").checkErr;

const Container = @This();

rootfs: []const u8,
cmd: []const u8,
net: Net,
cgroup: Cgroup,
allocator: std.mem.Allocator,

pub fn init(rootfs: []const u8, cmd: []const u8, allocator: std.mem.Allocator) !Container {
    return .{
        .rootfs = rootfs,
        .cmd = cmd,
        .net = try Net.init(allocator),
        .allocator = allocator,
        .cgroup = try Cgroup.init(rootfs, allocator),
    };
}

fn initNamespaces(self: *Container) !void {
    try self.net.setUpBridge();
    try self.net.setupContainerNetNs(self.rootfs); // TODO generate unique name
    try self.net.createVethPair(self.rootfs);
    try self.net.setupDnsResolverConfig(self.rootfs);

    const res = linux.unshare(linux.CLONE.NEWNS | linux.CLONE.NEWPID | linux.CLONE.NEWUTS);
    try checkErr(res, error.Unshare);
}

fn setupRootDir(self: *Container) !void {
    try checkErr(linux.chroot(@ptrCast(self.rootfs)), error.Chroot);
    try checkErr(linux.chdir("/"), error.Chdir);
    try checkErr(linux.mount("proc", "proc", "proc", 0, 0), error.Mount);
    const name = "container";
    _ = linux.syscall2(.sethostname, @intFromPtr(&name[0]), name.len);
}

pub fn run(self: *Container) !void {
    try self.cgroup.enterCgroup();
    try self.initNamespaces();

    // must create a child process to enter the new PID namespace
    const pid = try std.os.fork();
    if (pid == 0) {
        try self.setupRootDir();
        std.process.execv(std.heap.page_allocator, &.{self.cmd}) catch return error.ExecErr;
    } else {
        const wait_res = std.os.waitpid(pid, 0);
        if (wait_res.status != 0) {
            return error.RunFailed;
        }
    }
}
