const LinkMessage = @import("link.zig");
const RtNetLink = @import("../rtnetlink.zig");
const std = @import("std");
const linux = std.os.linux;

const LinkSet = @This();

pub const Options = struct {
    index: c_int,
    name: ?[]const u8 = null,
    master: ?c_int = null,
    up: bool = false,
    down: bool = false,
    nomaster: bool = false,
};

msg: LinkMessage,
nl: *RtNetLink,
opts: Options,
pub fn init(allocator: std.mem.Allocator, nl: *RtNetLink, options: Options) !LinkSet {
    var msg = LinkMessage.init(allocator, .set);
    msg.msg.header.index = options.index;
    return .{ .msg = msg, .nl = nl, .opts = options };
}

fn up(self: *LinkSet) void {
    self.msg.msg.header.flags |= LinkMessage.Flags.UP;
    self.msg.msg.header.change |= LinkMessage.Flags.UP;
}

fn down(self: *LinkSet) void {
    self.msg.msg.header.flags &= ~LinkMessage.Flags.UP;
    self.msg.msg.header.change |= LinkMessage.Flags.UP;
}

fn name(self: *LinkSet, value: []const u8) !void {
    try self.msg.addAttr(.{ .name = value });
}

fn master(self: *LinkSet, idx: c_int) !void {
    try self.msg.addAttr(.{ .master = @intCast(idx) });
}

fn nomaster(self: *LinkSet) !void {
    try self.msg.addAttr(.{ .master = 0 });
}

fn applyOptions(self: *LinkSet) !void {
    if (self.opts.up) {
        self.up();
    } else if (self.opts.down) {
        self.down();
    }

    if (self.opts.name) |val| {
        try self.name(val);
    }

    if (self.opts.master) |val| {
        try self.master(val);
    } else if (self.opts.nomaster) {
        try self.nomaster();
    }
}

pub fn exec(self: *LinkSet) !void {
    try self.applyOptions();
    try self.nl.send(try self.msg.compose());
    return self.nl.recv_ack();
}