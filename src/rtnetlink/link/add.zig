const LinkMessage = @import("link.zig");
const RtNetLink = @import("../rtnetlink.zig");
const std = @import("std");
const linux = std.os.linux;

const LinkAdd = @This();

pub const Options = struct {
    name: ?[]const u8 = null,
    veth: ?struct { []const u8, []const u8 } = null,
    bridge: ?[]const u8 = null,
};

msg: LinkMessage,
nl: *RtNetLink,
opts: Options,

pub fn init(allocator: std.mem.Allocator, nl: *RtNetLink, options: Options) !LinkAdd {
    const msg = LinkMessage.init(allocator, .create);
    return LinkAdd{ .msg = msg, .nl = nl, .opts = options };
}

fn name(self: *LinkAdd, val: []const u8) !void {
    try self.msg.addAttr(.{ .name = val });
}

fn veth(self: *LinkAdd, if_name: []const u8, peer_name: []const u8) !void {
    try self.name(if_name);

    var peer_info = LinkMessage.LinkInfo.init(self.msg.allocator);
    try peer_info.attrs.append(.{ .name = peer_name });

    try self.msg.addAttr(.{
        .link_info = .{ .info = .{ .peer_info = peer_info }, .kind = .veth },
    });
}

fn bridge(self: *LinkAdd, br_name: []const u8) !void {
    try self.msg.addAttr(.{ .link_info = .{ .kind = .bridge } });
    try self.msg.addAttr(.{ .name = br_name });
}

fn applyOptions(self: *LinkAdd) !void {
    if (self.opts.name) |val| {
        try self.name(val);
    }
    if (self.opts.veth) |val| {
        try self.veth(val[0], val[1]);
    }
    if (self.opts.bridge) |val| {
        try self.bridge(val);
    }
}

pub fn exec(self: *LinkAdd) !void {
    try self.applyOptions();
    try self.nl.send(try self.msg.compose());
    return self.nl.recv_ack();
}
