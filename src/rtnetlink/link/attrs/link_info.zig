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

const Info = union(enum) {
    peer_info: link.LinkInfo,
    fn info_type(self: Info) linux.IFLA {
        return switch (self) {
            .peer_info => VethInfoPeer,
        };
    }

    fn encode(self: Info, buff: []u8) !usize {
        const header = linux.rtattr{ .len = @intCast(self.size()), .type = self.info_type() };
        @memcpy(buff[0..@sizeOf(linux.rtattr)], std.mem.asBytes(&header));
        switch (self) {
            inline else => |v| {
                try v.encode(buff[@sizeOf(linux.rtattr)..]);
            },
        }

        return header.len;
    }

    fn size(self: Info) usize {
        const val_size = switch (self) {
            inline else => |v| v.size(),
        };
        return nalign(val_size + @sizeOf(linux.rtattr));
    }
};

pub const LinkInfoAttr = struct {
    info: Info,
    kind: Kind,

    pub fn encode(self: LinkInfoAttr, buff: []u8) anyerror!usize {
        var start: usize = 0;
        const len = self.size();

        // link info kind
        start += try self.kind.encode(buff[0..]);

        // link info data
        const hdr3 = linux.rtattr{ .len = @intCast(len - start), .type = LinkInfoData };
        @memcpy(buff[start .. start + @sizeOf(linux.rtattr)], std.mem.asBytes(&hdr3));
        start += @sizeOf(linux.rtattr);

        _ = try self.info.encode(buff[start..]);
        return len;
    }

    pub fn size(self: LinkInfoAttr) usize {
        const len = self.info.size() + @sizeOf(linux.rtattr) + self.kind.size();
        return nalign(len);
    }
};
