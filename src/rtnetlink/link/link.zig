const std = @import("std");
const linux = std.os.linux;

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

pub const LinkAttribute = union(enum) {
    name: []const u8,
    address: [4]u8,

    pub fn size(self: LinkAttribute) usize {
        const val_len = switch (self) {
            .name => |val| val.len + 1,
            .address => |val| val.len,
        };

        return std.mem.alignForward(usize, val_len + @sizeOf(linux.rtattr), 4);
    }

    pub fn getAttr(self: LinkAttribute) linux.rtattr {
        var attr: linux.rtattr = switch (self) {
            .name => |val| .{ .len = @intCast(val.len + 1), .type = .IFNAME },
            .address => |val| .{ .len = @intCast(val.len), .type = .ADDRESS },
        };

        attr.len = @intCast(std.mem.alignForward(usize, attr.len + @sizeOf(linux.rtattr), 4));
        return attr;
    }
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
};

hdr: linux.nlmsghdr,
link_header: linux.ifinfomsg,
attrs: std.ArrayList(LinkAttribute),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, req_type: RequestType) Link {
    return .{
        .hdr = .{
            .type = req_type.toMsgType(),
            .flags = linux.NLM_F_REQUEST | linux.NLM_F_ACK,
            .len = 0,
            .pid = 0,
            .seq = 0,
        },
        .link_header = .{
            .family = linux.AF.UNSPEC,
            .type = 1, // ethernet device
            .flags = 0,
            .index = 0,
            .change = 0,
        },
        .attrs = std.ArrayList(LinkAttribute).init(allocator),
        .allocator = allocator,
    };
}

pub fn compose(self: *Link) ![]u8 {
    var size: usize = @sizeOf(linux.ifinfomsg) + @sizeOf(linux.nlmsghdr);
    for (self.attrs.items) |a| {
        size += a.size();
    }
    // size = std.mem.alignForward(usize, size, 4);
    var buff = try self.allocator.alloc(u8, size);
    self.hdr.len = @intCast(size);

    // copy data into buff
    @memset(buff, 0);
    var start: usize = 0;
    @memcpy(buff[0..@sizeOf(linux.nlmsghdr)], std.mem.asBytes(&self.hdr));
    start += @sizeOf(linux.nlmsghdr);
    @memcpy(buff[start .. start + @sizeOf(linux.ifinfomsg)], std.mem.asBytes(&self.link_header));
    start += @sizeOf(linux.ifinfomsg);

    for (self.attrs.items) |attr| {
        const attr_header = attr.getAttr();
        @memcpy(buff[start .. start + @sizeOf(linux.rtattr)], std.mem.asBytes(&attr_header));
        start += @sizeOf(linux.rtattr);

        switch (attr) {
            .name => |n| {
                @memcpy(buff[start .. start + n.len], n);
                buff[start + n.len] = 0;
                start += n.len + 1;
            },
            else => @panic("invalid attr"),
        }
    }

    return buff;
}

pub fn addAttr(self: *Link, attr: LinkAttribute) !void {
    try self.attrs.append(attr);
}
