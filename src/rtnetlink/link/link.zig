const std = @import("std");
const linux = std.os.linux;
const LinkAttribute = @import("attrs.zig").LinkAttribute;

const Link = @This();

pub const Flags = struct {
    pub const UP: c_uint = 1 << 0;
    pub const BROADCAST: c_uint = 1 << 1;
    pub const DEBUG: c_uint = 1 << 2;
    pub const LOOPBACK: c_uint = 1 << 3;
    pub const POINTOPOINT: c_uint = 1 << 4;
    pub const NOTRAILERS: c_uint = 1 << 5;
    pub const RUNNING: c_uint = 1 << 6;
    pub const NOARP: c_uint = 1 << 7;
    pub const PROMISC: c_uint = 1 << 8;
    pub const ALLMULTI: c_uint = 1 << 9;
    pub const MASTER: c_uint = 1 << 10;
    pub const SLAVE: c_uint = 1 << 11;
    pub const MULTICAST: c_uint = 1 << 12;
    pub const PORTSEL: c_uint = 1 << 13;
    pub const AUTOMEDIA: c_uint = 1 << 14;
    pub const DYNAMIC: c_uint = 1 << 15;
    pub const LOWER_UP: c_uint = 1 << 16;
    pub const DORMANT: c_uint = 1 << 17;
    pub const ECHO: c_uint = 1 << 18;
};

const RequestType = enum {
    create,
    delete,
    get,
    set,

    fn toMsgType(self: RequestType) linux.NetlinkMessageType {
        return switch (self) {
            .create => .RTM_NEWLINK,
            .delete => .RTM_DELLINK,
            .get => .RTM_GETLINK,
            .set => .RTM_SETLINK,
        };
    }

    fn getFlags(self: RequestType) u16 {
        var flags: u16 = linux.NLM_F_REQUEST | linux.NLM_F_ACK;
        switch (self) {
            .create => flags |= linux.NLM_F_CREATE,
            else => {},
        }

        return flags;
    }
};

pub const LinkInfo = struct {
    header: linux.ifinfomsg,
    attrs: std.ArrayList(LinkAttribute),

    pub fn init(allocator: std.mem.Allocator) LinkInfo {
        return .{
            .header = .{
                .family = linux.AF.UNSPEC,
                .type = 1, // ethernet device
                .flags = 0,
                .index = 0,
                .change = 0,
            },

            .attrs = std.ArrayList(LinkAttribute).init(allocator),
        };
    }

    pub fn size(self: *const LinkInfo) usize {
        var s: usize = @sizeOf(linux.ifinfomsg);
        for (self.attrs.items) |a| {
            s += a.size();
        }
        return s;
    }

    pub fn encode(self: *const LinkInfo, buff: []u8) !void {
        var start: usize = 0;
        @memcpy(buff[start .. start + @sizeOf(linux.ifinfomsg)], std.mem.asBytes(&self.header));
        start += @sizeOf(linux.ifinfomsg);

        for (self.attrs.items) |attr| {
            start += try attr.encode(buff[start..]);
        }
    }
};

hdr: linux.nlmsghdr,
link_message: LinkInfo,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, req_type: RequestType) Link {
    return .{
        .hdr = .{
            .type = req_type.toMsgType(),
            .flags = req_type.getFlags(),
            .len = 0,
            .pid = 0,
            .seq = 0,
        },
        .link_message = LinkInfo.init(allocator),
        .allocator = allocator,
    };
}

pub fn compose(self: *Link) ![]u8 {
    const size: usize = self.link_message.size() + @sizeOf(linux.nlmsghdr);

    var buff = try self.allocator.alloc(u8, size);
    self.hdr.len = @intCast(size);

    // copy data into buff
    @memset(buff, 0);
    var start: usize = 0;
    @memcpy(buff[0..@sizeOf(linux.nlmsghdr)], std.mem.asBytes(&self.hdr));
    start += @sizeOf(linux.nlmsghdr);
    try self.link_message.encode(buff[start..]);

    return buff;
}

pub fn addAttr(self: *Link, attr: LinkAttribute) !void {
    try self.link_message.attrs.append(attr);
}
