const std = @import("std");
const log = std.log;
const linux = std.os.linux;
const Net = @import("net.zig");

const utils = @import("utils.zig");
const checkErr = utils.checkErr;

pub fn main() !void {
    const args = std.os.argv;
    if (args.len < 2) {
        log.info("missing rootfs path", .{});
        return;
    }

    const rootfs = std.mem.span(args[1]);
    if (args.len > 2 and std.mem.eql(u8, std.mem.span(args[2]), "child")) {
        return childfn(rootfs);
    }

    var net = try Net.init(std.heap.page_allocator);
    try net.setUpBridge();
    try net.setupContainerNetNs(rootfs); // TODO generate unique name

    const res = linux.unshare(linux.CLONE.NEWNS | linux.CLONE.NEWPID | linux.CLONE.NEWUTS);
    try checkErr(res, error.Unshare);

    var child = std.ChildProcess.init(&.{ "/proc/self/exe", rootfs, "child" }, std.heap.page_allocator);
    _ = try child.spawnAndWait();
}

fn childfn(rootfs: []const u8) !void {
    try checkErr(linux.chroot(@ptrCast(rootfs)), error.Chroot);
    try checkErr(linux.chdir("/"), error.Chdir);
    try checkErr(linux.mount("proc", "proc", "proc", 0, 0), error.Mount);

    const name = "container";
    _ = linux.syscall2(.sethostname, @intFromPtr(&name[0]), name.len);

    std.process.execv(std.heap.page_allocator, &.{"/bin/sh"}) catch return error.ExecErr;
}
