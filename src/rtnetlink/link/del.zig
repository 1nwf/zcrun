const LinkMessage = @import("link.zig");
const RtNetLink = @import("../rtnetlink.zig");
const std = @import("std");
const linux = std.os.linux;

const LinkDel = @This();

msg: LinkMessage,
nl: *RtNetLink,

pub fn init(allocator: std.mem.Allocator, nl: *RtNetLink, index: c_int) LinkDel {
    var msg = LinkMessage.init(allocator, .delete);
    msg.msg.header.index = index;
    return LinkDel{ .msg = msg, .nl = nl };
}

pub fn exec(self: *LinkDel) !void {
    const data = try self.msg.compose();
    defer self.msg.allocator.free(data);

    try self.nl.send(data);
    return self.nl.recv_ack();
}
