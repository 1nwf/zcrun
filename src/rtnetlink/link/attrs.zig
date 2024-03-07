const std = @import("std");
const linux = std.os.linux;
const link = @import("link.zig");

const LinkInfoKind: linux.IFLA = @enumFromInt(1);
const LinkInfoData: linux.IFLA = @enumFromInt(2);
const VethInfoPeer: linux.IFLA = @enumFromInt(1);

fn nsalign(value: usize) usize {
    return std.mem.alignForward(usize, value, 4);
}

const LinkInfoAttr = struct {
    const Kind = enum {
        veth,
        fn size(self: Kind) usize {
            return nsalign(@tagName(self).len + @sizeOf(linux.rtattr));
        }

        fn encode(self: Kind, buff: []u8) !usize {
            const attr_size = @sizeOf(linux.rtattr);
            const hdr = linux.rtattr{ .len = @intCast(self.size()), .type = LinkInfoKind };
            @memcpy(buff[0..attr_size], std.mem.asBytes(&hdr));

            const value = @tagName(self);
            @memcpy(buff[attr_size .. attr_size + value.len], value);
            return hdr.len;
        }
    };

    peer_info: link.LinkInfo,
    kind: Kind,

    pub fn encode(self: LinkInfoAttr, buff: []u8) anyerror!usize {
        var start: usize = 0;
        const attr_size = @sizeOf(linux.rtattr);

        // link info kind
        start += try self.kind.encode(buff[0..]);

        // link info data
        const hdr3 = linux.rtattr{ .len = @intCast(nsalign(self.peer_info.size() + attr_size * 2)), .type = LinkInfoData };
        const hdr4 = linux.rtattr{ .len = @intCast(nsalign(self.peer_info.size() + attr_size)), .type = VethInfoPeer };
        @memcpy(buff[start .. start + attr_size], std.mem.asBytes(&hdr3));
        start += attr_size;
        @memcpy(buff[start .. start + attr_size], std.mem.asBytes(&hdr4));
        start += attr_size;

        // peer link info
        try self.peer_info.encode(buff[start..]);
        return self.size();
    }

    pub fn size(self: LinkInfoAttr) usize {
        const len = std.mem.alignForward(usize, self.peer_info.size(), 4) + (@sizeOf(linux.rtattr) * 2) + self.kind.size();
        return std.mem.alignForward(usize, len, 4);
    }
};

pub const LinkAttribute = union(enum) {
    name: []const u8,
    address: [4]u8,
    link_info: LinkInfoAttr,

    pub fn size(self: LinkAttribute) usize {
        const val_len = switch (self) {
            .name => |val| val.len + 1,
            .address => |val| val.len,
            .link_info => |val| val.size(),
        };

        return std.mem.alignForward(usize, val_len + @sizeOf(linux.rtattr), 4);
    }

    fn getAttr(self: LinkAttribute) linux.rtattr {
        var attr: linux.rtattr = switch (self) {
            .name => |val| .{ .len = @intCast(val.len + 1), .type = .IFNAME },
            .address => |val| .{ .len = @intCast(val.len), .type = .ADDRESS },
            .link_info => |val| .{ .len = @intCast(val.size()), .type = .LINKINFO },
        };

        attr.len = @intCast(std.mem.alignForward(usize, attr.len + @sizeOf(linux.rtattr), 4));
        return attr;
    }

    pub fn encode(self: LinkAttribute, buff: []u8) !usize {
        const header = self.getAttr();
        @memcpy(buff[0..@sizeOf(linux.rtattr)], std.mem.asBytes(&header));
        const len = try self.encodeVal(buff[@sizeOf(linux.rtattr)..]) + @sizeOf(linux.rtattr);
        return std.mem.alignForward(usize, len, 4);
    }

    inline fn encodeVal(self: LinkAttribute, buff: []u8) !usize {
        return switch (self) {
            .name => |val| {
                @memcpy(buff[0..val.len], val);
                buff[val.len] = 0;
                return val.len + 1;
            },
            .link_info => |val| {
                return try val.encode(buff);
            },
            else => 0,
        };
    }
};
