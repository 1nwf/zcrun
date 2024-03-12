const std = @import("std");
const linux = std.os.linux;
const log = std.log;
const NetLink = @import("../rtnetlink.zig");
const RouteMessage = @import("route.zig");
const Attr = @import("attrs.zig").RtAttr;
const nalign = @import("../utils.zig").nalign;

const Get = @This();

msg: RouteMessage,
nl: *NetLink,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, nl: *NetLink) Get {
    var msg = RouteMessage.init(allocator, .get);
    msg.msg.hdr.scope = .Universe;
    msg.msg.hdr.type = .Unspec;
    msg.msg.hdr.table = .Unspec;
    msg.msg.hdr.protocol = .Unspec;

    msg.hdr.flags |= linux.NLM_F_DUMP;

    return .{
        .nl = nl,
        .msg = msg,
        .allocator = allocator,
    };
}

pub fn exec(self: *Get) ![]RouteMessage {
    const msg = try self.msg.compose();
    defer self.allocator.free(msg);

    try self.nl.send(msg);
    return try self.recv();
}

fn recv(self: *Get) ![]RouteMessage {
    var buff: [4096]u8 = undefined;

    var n = try self.nl.recv(&buff);

    var response = std.ArrayList(RouteMessage).init(self.allocator);
    errdefer response.deinit();
    outer: while (n != 0) {
        var d: usize = 0;
        while (d < n) {
            const msg = (try self.parseMessage(buff[d..])) orelse break :outer;
            try response.append(msg);
            d += msg.hdr.len;
        }
        n = try self.nl.recv(&buff);
    }
    return response.toOwnedSlice();
}

fn parseMessage(self: *Get, buff: []u8) !?RouteMessage {
    const header = std.mem.bytesAsValue(linux.nlmsghdr, buff[0..@sizeOf(linux.nlmsghdr)]);
    if (header.type == .ERROR) {
        const response = std.mem.bytesAsValue(NetLink.NlMsgError, buff[0..]);
        try NetLink.handle_ack(response.*);
        unreachable;
    } else if (header.type == .DONE) {
        return null;
    }

    var msg = RouteMessage.init(self.allocator, .create);
    errdefer msg.deinit();

    const len = header.len;
    msg.hdr = header.*;

    const hdr = std.mem.bytesAsValue(RouteMessage.RouteHeader, buff[@sizeOf(linux.nlmsghdr)..]);
    msg.msg.hdr = hdr.*;

    var start: usize = @sizeOf(RouteMessage.RouteHeader) + @sizeOf(linux.nlmsghdr);
    while (start < len) {
        const attr = std.mem.bytesAsValue(Attr, buff[start..]);
        // TODO: parse more attrs
        switch (attr.type) {
            .Gateway => {
                try msg.addAttr(.{ .gateway = buff[start + @sizeOf(Attr) .. start + attr.len][0..4].* });
            },
            .Oif => {
                const value = std.mem.bytesAsValue(u32, buff[start + @sizeOf(Attr) .. start + attr.len]);
                try msg.addAttr(.{ .output_if = value.* });
            },
            else => {},
        }

        start += nalign(attr.len);
    }

    return msg;
}
