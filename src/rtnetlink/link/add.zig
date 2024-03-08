const LinkMessage = @import("link.zig");
const RtNetLink = @import("../rtnetlink.zig");
const std = @import("std");
const linux = std.os.linux;

const LinkAdd = @This();

msg: LinkMessage,
nl: *RtNetLink,
pub fn init(allocator: std.mem.Allocator, nl: *RtNetLink) LinkAdd {
    const msg = LinkMessage.init(allocator, .create);
    return .{ .msg = msg, .nl = nl };
}

pub fn name(self: *LinkAdd, val: []const u8) !void {
    try self.msg.addAttr(.{ .name = val });
}

pub fn veth(self: *LinkAdd, if_name: []const u8, peer_name: []const u8) !void {
    try self.name(if_name);

    var peer_info = LinkMessage.LinkInfo.init(self.msg.allocator);
    try peer_info.attrs.append(.{ .name = peer_name });

    try self.msg.addAttr(.{
        .link_info = .{ .info = .{ .peer_info = peer_info }, .kind = .veth },
    });
}

pub fn bridge(self: *LinkAdd, br_name: []const u8) !void {
    try self.msg.addAttr(.{ .link_info = .{ .kind = .bridge } });
    try self.msg.addAttr(.{ .name = br_name });
}

pub fn exec(self: *LinkAdd) !void {
    try self.nl.send(try self.msg.compose());
    return self.nl.recv_ack();
}
