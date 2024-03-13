const std = @import("std");
const log = std.log;
const linux = std.os.linux;
const Net = @import("net.zig");
const Cgroup = @import("cgroup.zig");
const checkErr = @import("utils.zig").checkErr;

const Container = @This();

rootfs: []const u8,
name: []const u8,
cmd: []const u8,

net: Net,
cgroup: Cgroup,
allocator: std.mem.Allocator,

pub fn init(name: []const u8, rootfs: []const u8, cmd: []const u8, allocator: std.mem.Allocator) !Container {
    return .{
        .name = name,
        .rootfs = rootfs,
        .cmd = cmd,

        .net = try Net.init(allocator, name),
        .allocator = allocator,
        .cgroup = try Cgroup.init(name, allocator),
    };
}

fn initNetwork(self: *Container) !void {
    try self.net.enableNat();
    try self.net.setupContainerNetNs();
    try self.net.setUpBridge();
    try self.net.createVethPair();
    try self.net.setupDnsResolverConfig(self.rootfs);
}

fn initNamespaces(self: *Container) !void {
    try self.initNetwork();
    const res = linux.unshare(linux.CLONE.NEWNS | linux.CLONE.NEWPID | linux.CLONE.NEWUTS);
    try checkErr(res, error.Unshare);
}

fn mountVfs(_: *Container) !void {
    try checkErr(linux.mount("proc", "proc", "proc", 0, 0), error.MountProc);
    try checkErr(linux.mount("tmpfs", "tmp", "tmpfs", 0, 0), error.MountTmpFs);
    try checkErr(linux.mount("sysfs", "sys", "sysfs", 0, 0), error.MountSysFs);
}

fn setupRootDir(self: *Container) !void {
    try checkErr(linux.chroot(@ptrCast(self.rootfs)), error.Chroot);
    try checkErr(linux.chdir("/"), error.Chdir);
    try self.mountVfs();

    _ = linux.syscall2(.sethostname, @intFromPtr(self.name.ptr), self.name.len);
}

pub fn run(self: *Container) !void {
    try self.initNamespaces();
    try self.cgroup.enterCgroup();

    // must create a child process to enter the new PID namespace
    const pid = try std.os.fork();
    if (pid == 0) {
        try self.setupRootDir();
        std.process.execv(self.allocator, &.{self.cmd}) catch return error.ExecErr;
    } else {
        const wait_res = std.os.waitpid(pid, 0);
        if (wait_res.status != 0) {
            return error.RunFailed;
        }
    }
}

pub fn deinit(self: *Container) void {
    self.net.deinit() catch {};
}
