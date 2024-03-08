const LinkMessage = @import("link.zig");
const RtNetLink = @import("../rtnetlink.zig");
const std = @import("std");
const log = std.log;
const nalign = @import("../utils.zig").nalign;
const linux = std.os.linux;

const LinkGet = @This();

msg: LinkMessage,
nl: *RtNetLink,
pub fn init(allocator: std.mem.Allocator, nl: *RtNetLink) LinkGet {
    const msg = LinkMessage.init(allocator, .get);
    return .{ .msg = msg, .nl = nl };
}

pub fn name(self: *LinkGet, value: []const u8) !void {
    try self.msg.addAttr(.{ .name = value });
}

pub fn exec(self: *LinkGet) !LinkMessage {
    try self.nl.send(try self.msg.compose());
    var buff: [512]u8 = undefined;
    const n = try self.nl.recv(&buff);
    var start: usize = 0;
    var link_info = LinkMessage.init(self.nl.allocator, .create); // req_type doesn't matter here

    const header = std.mem.bytesAsValue(linux.nlmsghdr, buff[0..@sizeOf(linux.nlmsghdr)]);
    if (header.type == .ERROR) {
        const response = std.mem.bytesAsValue(RtNetLink.NlMsgError, buff[0..]);
        try RtNetLink.handle_ack(response.*);
        unreachable;
    }
    start += @sizeOf(linux.nlmsghdr);
    link_info.hdr = header.*;

    log.info("header: {}", .{header});
    const ifinfo = std.mem.bytesAsValue(linux.ifinfomsg, buff[start .. start + @sizeOf(linux.ifinfomsg)]);
    start += @sizeOf(linux.ifinfomsg);
    link_info.msg.header = ifinfo.*;

    log.info("ifinfo: {}", .{ifinfo});
    while (start < n) {
        const rtattr = std.mem.bytesAsValue(linux.rtattr, buff[start .. start + @sizeOf(linux.rtattr)]);
        switch (rtattr.type) {
            .IFNAME => {
                const ifname = buff[start + @sizeOf(linux.rtattr) .. start + rtattr.len - 1]; // skip null terminating byte
                log.info("name: {s}", .{ifname});
                try link_info.addAttr(.{ .name = ifname });
            },
            else => {},
        }
        start += nalign(rtattr.len);
    }

    // TODO: handle multipart messages
    // parse ACK/NACK response
    try self.nl.recv_ack();
    return link_info;
}
