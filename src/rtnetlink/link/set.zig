const LinkMessage = @import("link.zig");
const RtNetLink = @import("../rtnetlink.zig");
const std = @import("std");
const linux = std.os.linux;

const LinkSet = @This();

msg: LinkMessage,
nl: *RtNetLink,
pub fn init(allocator: std.mem.Allocator, nl: *RtNetLink, index: c_int) LinkSet {
    var msg = LinkMessage.init(allocator, .set);
    msg.msg.header.index = index;

    return .{ .msg = msg, .nl = nl };
}

pub fn up(self: *LinkSet) void {
    self.msg.msg.header.flags |= LinkMessage.Flags.UP;
    self.msg.msg.header.change |= LinkMessage.Flags.UP;
}

pub fn down(self: *LinkSet) void {
    self.msg.msg.header.flags &= ~LinkMessage.Flags.UP;
    self.msg.msg.header.change |= LinkMessage.Flags.UP;
}

pub fn name(self: *LinkSet, value: []const u8) !void {
    try self.msg.addAttr(.{ .name = value });
}

pub fn master(self: *LinkSet, idx: c_int) !void {
    try self.msg.addAttr(.{ .master = @intCast(idx) });
}

pub fn nomaster(self: *LinkSet) !void {
    try self.msg.addAttr(.{ .master = 0 });
}

pub fn exec(self: *LinkSet) !void {
    try self.nl.send(try self.msg.compose());
    return self.nl.recv_ack();
}
