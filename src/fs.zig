const std = @import("std");
const linux = std.os.linux;
const checkErr = @import("utils.zig").checkErr;

rootfs: []const u8,

const Fs = @This();

pub fn init(rootfs: []const u8) Fs {
    return .{ .rootfs = rootfs };
}

pub fn setup(self: *Fs) !void {
    try checkErr(linux.chroot(@ptrCast(self.rootfs)), error.Chroot);
    try checkErr(linux.chdir("/"), error.Chdir);

    // TODO: mount more filesystems
    // from list: https://github.com/opencontainers/runtime-spec/blob/main/config-linux.md
    try checkErr(linux.mount("proc", "proc", "proc", 0, 0), error.MountProc);
    try checkErr(linux.mount("tmpfs", "tmp", "tmpfs", 0, 0), error.MountTmpFs);
    // ignore sysfs mount error since it can fail when
    // executed in a new user namespace
    _ = linux.mount("sysfs", "sys", "sysfs", 0, 0);
}
