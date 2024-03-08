const Addr = @import("address.zig");
const RtNetLink = @import("../rtnetlink.zig");
const std = @import("std");
const linux = std.os.linux;

const AddrAdd = @This();

msg: Addr,
nl: *RtNetLink,
pub fn init(allocator: std.mem.Allocator, nl: *RtNetLink, index: u32, addr: [4]u8, prefix_len: u8) !AddrAdd {
    var msg = Addr.init(allocator, .create);
    msg.msg.hdr.index = index;
    msg.msg.hdr.prefix_len = prefix_len;
    try msg.addAttr(.{ .address = addr });
    try msg.addAttr(.{ .local = addr });

    if (prefix_len == 32) {
        try msg.addAttr(.{ .broadcast = addr });
    } else {
        const brd = (@as(u32, 0xffff_ffff) >> @intCast(prefix_len)) | std.mem.bytesAsValue(u32, &addr).*;
        try msg.addAttr(.{ .broadcast = std.mem.toBytes(brd) });
    }

    return .{ .msg = msg, .nl = nl };
}

pub fn exec(self: *AddrAdd) !void {
    try self.nl.send(try self.msg.compose());
    return self.nl.recv_ack();
}
