const LinkMessage = @import("link.zig");
const RtNetLink = @import("../rtnetlink.zig");
const std = @import("std");
const linux = std.os.linux;

const LinkSet = @This();

msg: LinkMessage,
nl: *RtNetLink,
pub fn init(allocator: std.mem.Allocator, nl: *RtNetLink) LinkSet {
    const msg = LinkMessage.init(allocator, .set);
    return .{ .msg = msg, .nl = nl };
}

pub fn up(self: *LinkSet) void {
    self.msg.link_message.header.flags |= LinkMessage.Flags.UP;
    self.msg.link_message.header.change |= LinkMessage.Flags.UP;
}

pub fn down(self: *LinkSet) void {
    self.msg.link_message.header.flags &= ~LinkMessage.Flags.UP;
    self.msg.link_message.header.change |= LinkMessage.Flags.UP;
}

pub fn name(self: *LinkSet, value: []const u8) !void {
    try self.msg.addAttr(.{ .name = value });
}

pub fn exec(self: *LinkSet) !void {
    try self.nl.send(try self.msg.compose());
    return self.nl.recv_ack();
}
