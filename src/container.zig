const std = @import("std");
const log = std.log;
const linux = std.os.linux;
const Net = @import("net.zig");
const Cgroup = @import("cgroup.zig");
const checkErr = @import("utils.zig").checkErr;
const c = @cImport(@cInclude("signal.h"));

const ChildProcessArgs = struct {
    container: *Container,
    pipe: [2]i32,
    uid: linux.uid_t,
    gid: linux.gid_t,
};

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

fn mountVfs(_: *Container) !void {
    try checkErr(linux.mount("proc", "proc", "proc", 0, 0), error.MountProc);
    try checkErr(linux.mount("tmpfs", "tmp", "tmpfs", 0, 0), error.MountTmpFs);
    // ignore sysfs mount error since it can fail when
    // executed in a new user namespace
    _ = linux.mount("sysfs", "sys", "sysfs", 0, 0);
}

fn setupRootDir(self: *Container) !void {
    try checkErr(linux.chroot(@ptrCast(self.rootfs)), error.Chroot);
    try checkErr(linux.chdir("/"), error.Chdir);
    try self.mountVfs();

    _ = linux.syscall2(.sethostname, @intFromPtr(self.name.ptr), self.name.len);
}

pub fn run(self: *Container) !void {
    // setup network virtual interfaces and namespace
    try self.initNetwork();
    // enter container cgroup
    try self.cgroup.enterCgroup();

    var childp_args = ChildProcessArgs{ .container = self, .pipe = undefined, .uid = 0, .gid = 0 };
    try checkErr(linux.pipe(&childp_args.pipe), error.Pipe);
    var stack = try self.allocator.alloc(u8, 1024 * 1024);
    var ctid: i32 = 0;
    var ptid: i32 = 0;
    const clone_flags: u32 = linux.CLONE.NEWNS | linux.CLONE.NEWPID | linux.CLONE.NEWUTS | linux.CLONE.NEWIPC | linux.CLONE.NEWUSER | c.SIGCHLD;
    const pid = linux.clone(childFn, @intFromPtr(&stack[0]) + stack.len, clone_flags, @intFromPtr(&childp_args), &ptid, 0, &ctid);
    try checkErr(pid, error.CloneFailed);
    std.os.close(childp_args.pipe[0]);

    self.createUserRootMappings(@intCast(pid)) catch @panic("creating root user mapping failed");

    // signal done by writing to pipe
    const buff = [_]u8{0};
    _ = try std.os.write(childp_args.pipe[1], &buff);

    const wait_res = std.os.waitpid(@intCast(pid), 0);
    if (wait_res.status != 0) {
        return error.CmdFailed;
    }
}

export fn childFn(a: usize) u8 {
    const arg: *ChildProcessArgs = @ptrFromInt(a);
    std.os.close(arg.pipe[1]);
    // block until parent sets up needed resources
    {
        var buff = [_]u8{1};
        _ = std.os.read(arg.pipe[0], &buff) catch @panic("pipe read failed");
    }

    // sets the uid and gid inside the container as root
    // this should be configurable in future
    checkErr(linux.setreuid(arg.uid, arg.uid), error.UID) catch @panic("unable to set uid");
    checkErr(linux.setregid(arg.gid, arg.gid), error.GID) catch @panic("unable to set gid");

    arg.container.setupRootDir() catch |e| {
        log.err("{}", .{e});
        @panic("setup root dir failed");
    };

    std.process.execv(arg.container.allocator, &.{arg.container.cmd}) catch @panic("errr");
}

fn createUserRootMappings(self: *Container, pid: linux.pid_t) !void {
    const uidmap_path = try std.fmt.allocPrint(self.allocator, "/proc/{}/uid_map", .{pid});
    defer self.allocator.free(uidmap_path);
    const gidmap_path = try std.fmt.allocPrint(self.allocator, "/proc/{}/gid_map", .{pid});
    defer self.allocator.free(gidmap_path);

    const uid_map = try std.fs.openFileAbsolute(uidmap_path, .{ .mode = .write_only });
    defer uid_map.close();
    const gid_map = try std.fs.openFileAbsolute(gidmap_path, .{ .mode = .write_only });
    defer gid_map.close();

    // map root inside user namespace to the "nobody" user and group outside the namespace
    _ = try uid_map.write("0 65534 1");
    _ = try gid_map.write("0 65534 1");
}

pub fn deinit(self: *Container) void {
    self.net.deinit() catch {};
}
