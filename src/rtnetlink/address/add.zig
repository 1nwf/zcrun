const Addr = @import("address.zig");
const RtNetLink = @import("../rtnetlink.zig");
const std = @import("std");
const linux = std.os.linux;

const AddrAdd = @This();

pub const Options = struct {
    index: c_int,
    addr: [4]u8,
    prefix_len: u8,
};

msg: Addr,
nl: *RtNetLink,
opts: Options,

pub fn init(allocator: std.mem.Allocator, nl: *RtNetLink, options: Options) AddrAdd {
    const msg = Addr.init(allocator, .create);
    return .{ .msg = msg, .nl = nl, .opts = options };
}

fn applyOptions(self: *AddrAdd) !void {
    self.msg.msg.hdr.index = @intCast(self.opts.index);
    self.msg.msg.hdr.prefix_len = self.opts.prefix_len;
    try self.msg.addAttr(.{ .address = self.opts.addr });
    try self.msg.addAttr(.{ .local = self.opts.addr });

    if (self.opts.prefix_len == 32) {
        try self.msg.addAttr(.{ .broadcast = self.opts.addr });
    } else {
        const brd = (@as(u32, 0xffff_ffff) >> @intCast(self.opts.prefix_len)) | std.mem.bytesAsValue(u32, &self.opts.addr).*;
        try self.msg.addAttr(.{ .broadcast = std.mem.toBytes(brd) });
    }
}

pub fn exec(self: *AddrAdd) !void {
    try self.applyOptions();

    const data = try self.msg.compose();
    defer self.msg.allocator.free(data);

    try self.nl.send(data);
    return self.nl.recv_ack();
}
