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
