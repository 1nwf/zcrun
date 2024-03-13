const std = @import("std");
const log = std.log;

// TODO: make sure that the ip address is not used
pub fn getRandomIpv4Addr() [4]u8 {
    const num = std.crypto.random.int(u8);
    return .{ 10, 0, 0, num };
}
