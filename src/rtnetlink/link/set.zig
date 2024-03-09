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
    netns_fd: ?linux.fd_t = null,
};

msg: LinkMessage,
nl: *RtNetLink,
opts: Options,
pub fn init(allocator: std.mem.Allocator, nl: *RtNetLink, options: Options) LinkSet {
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

    if (self.opts.netns_fd) |fd| {
        try self.msg.addAttr(.{ .netns_fd = fd });
    }
}

pub fn exec(self: *LinkSet) !void {
    try self.applyOptions();

    const data = try self.msg.compose();
    defer self.msg.allocator.free(data);

    try self.nl.send(data);
    return self.nl.recv_ack();
}
