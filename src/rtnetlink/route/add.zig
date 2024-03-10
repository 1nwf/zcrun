const std = @import("std");
const NetLink = @import("../rtnetlink.zig");
const RouteMessage = @import("route.zig");

pub const Options = struct {
    gateway: ?[4]u8 = null,
};

const Add = @This();
msg: RouteMessage,
nl: *NetLink,
opts: Options,

pub fn init(allocator: std.mem.Allocator, nl: *NetLink, opts: Options) Add {
    var msg = RouteMessage.init(allocator, .create);

    msg.msg.hdr.protocol = .Static;
    msg.msg.hdr.type = .Unicast;

    return .{
        .msg = msg,
        .opts = opts,
        .nl = nl,
    };
}

fn applyOptions(self: *Add) !void {
    if (self.opts.gateway) |addr| {
        try self.msg.addAttr(.{ .gateway = addr });
    }
}

pub fn exec(self: *Add) !void {
    try self.applyOptions();

    const data = try self.msg.compose();
    defer self.msg.allocator.free(data);

    try self.nl.send(data);
    try self.nl.recv_ack();
}
