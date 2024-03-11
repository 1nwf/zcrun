const std = @import("std");
const linux = std.os.linux;

pub const INFO_PATH = "/var/run/zcrun/containers/";
pub const NETNS_PATH = INFO_PATH ++ "netns/";
pub const BRIDGE_NAME = "zcrun0";

pub fn checkErr(val: usize, err: anyerror) !void {
    const e = linux.getErrno(val);
    if (e != .SUCCESS) {
        std.log.err("err: {}", .{e});
        return err;
    }
}

pub fn createDirIfNotExists(path: []const u8) !bool {
    std.fs.makeDirAbsolute(path) catch |e| {
        return switch (e) {
            error.PathAlreadyExists => false,
            else => e,
        };
    };
    return true;
}

pub fn createFileIfNotExists(path: []const u8) !bool {
    const f = std.fs.createFileAbsolute(path, .{ .exclusive = true }) catch |e| {
        return switch (e) {
            error.PathAlreadyExists => false,
            else => e,
        };
    };
    f.close();
    return true;
}
