const std = @import("std");
const link = @import("../link.zig");
const linux = std.os.linux;
const nalign = @import("../../utils.zig").nalign;

const LinkInfoKind: linux.IFLA = @enumFromInt(1);
const LinkInfoData: linux.IFLA = @enumFromInt(2);
const VethInfoPeer: linux.IFLA = @enumFromInt(1);

const Kind = enum {
    veth,

    fn size(self: Kind) usize {
        return nalign(@tagName(self).len + @sizeOf(linux.rtattr));
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

pub const LinkInfoAttr = struct {
    peer_info: link.LinkInfo,
    kind: Kind,

    pub fn encode(self: LinkInfoAttr, buff: []u8) anyerror!usize {
        var start: usize = 0;
        const attr_size = @sizeOf(linux.rtattr);

        // link info kind
        start += try self.kind.encode(buff[0..]);

        // link info data
        const hdr3 = linux.rtattr{ .len = @intCast(nalign(self.peer_info.size() + attr_size * 2)), .type = LinkInfoData };
        const hdr4 = linux.rtattr{ .len = @intCast(nalign(self.peer_info.size() + attr_size)), .type = VethInfoPeer };
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
