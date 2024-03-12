const std = @import("std");
const nalign = @import("../utils.zig").nalign;
const c = @cImport(@cInclude("linux/rtnetlink.h"));

comptime {
    std.debug.assert(@sizeOf(std.os.linux.rtattr) == @sizeOf(RtAttr));
}

pub const RtAttr = packed struct {
    len: u16,
    type: AttrType,
};

pub const AttrType = enum(u16) {
    Unspec = c.RTA_UNSPEC,
    Dst = c.RTA_DST,
    Src = c.RTA_SRC,
    Iif = c.RTA_IIF,
    Oif = c.RTA_OIF,
    Gateway = c.RTA_GATEWAY,
    Priority = c.RTA_PRIORITY,
    Prefsrc = c.RTA_PREFSRC,
    Metrics = c.RTA_METRICS,
    Multipath = c.RTA_MULTIPATH,
    Flow = c.RTA_FLOW,
    CacheInfo = c.RTA_CACHEINFO,
    Table = c.RTA_TABLE,
    Mark = c.RTA_MARK,
    Stats = c.RTA_MFC_STATS,
    Via = c.RTA_VIA,
    NewDst = c.RTA_NEWDST,
    Pref = c.RTA_PREF,
    Type = c.RTA_ENCAP_TYPE,
    Encap = c.RTA_ENCAP,
    Expires = c.RTA_EXPIRES,
    Pad = c.RTA_PAD,
    Uid = c.RTA_UID,
    Propagate = c.RTA_TTL_PROPAGATE,
    Proto = c.RTA_IP_PROTO,
    Sport = c.RTA_SPORT,
    Dport = c.RTA_DPORT,
    Id = c.RTA_NH_ID,
};
// TODO: support IPv6
pub const Attr = union(enum) {
    gateway: [4]u8,
    output_if: u32,

    fn getAttr(self: Attr) RtAttr {
        var attr: RtAttr = switch (self) {
            .gateway => |val| .{ .len = val.len, .type = .Gateway },
            .output_if => .{ .len = 4, .type = .Oif },
        };

        attr.len = @intCast(nalign(attr.len + @sizeOf(RtAttr)));
        return attr;
    }

    pub fn size(self: Attr) usize {
        const len = switch (self) {
            .gateway => |val| val.len,
            .output_if => 4,
        };
        return nalign(len + @sizeOf(RtAttr));
    }

    pub fn encode(self: Attr, buff: []u8) !usize {
        const header = self.getAttr();
        @memcpy(buff[0..@sizeOf(RtAttr)], std.mem.asBytes(&header));
        _ = try self.encodeVal(buff[@sizeOf(RtAttr)..]);
        return nalign(header.len);
    }

    inline fn encodeVal(self: Attr, buff: []u8) !usize {
        return switch (self) {
            .gateway => |val| {
                @memcpy(buff[0..val.len], &val);
                return val.len;
            },
            .output_if => |val| {
                @memcpy(buff[0..4], std.mem.asBytes(&val));
                return 4;
            },
        };
    }
};
