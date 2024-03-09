const std = @import("std");
const log = std.log;
const linux = std.os.linux;
const NetLink = @import("rtnetlink/rtnetlink.zig");

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

    const err = linux.unshare(linux.CLONE.NEWNS | linux.CLONE.NEWPID | linux.CLONE.NEWUTS);
    const code = linux.getErrno(err);
    if (code != .SUCCESS) {
        @panic("unshare err");
    }

    var child = std.ChildProcess.init(&.{ "/proc/self/exe", rootfs, "child" }, std.heap.page_allocator);
    _ = try child.spawnAndWait();
}

fn childfn(rootfs: []const u8) !void {
    _ = linux.chroot(@ptrCast(rootfs));
    _ = linux.chdir("/");
    _ = linux.mount("proc", "proc", "proc", 0, 0);

    const name = "container";
    _ = linux.syscall2(.sethostname, @intFromPtr(&name[0]), name.len);

    std.process.execv(std.heap.page_allocator, &.{"/bin/bash"}) catch return error.ExecErr;
}
