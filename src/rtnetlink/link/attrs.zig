const std = @import("std");
const linux = std.os.linux;
const link = @import("link.zig");
const nalign = @import("../utils.zig").nalign;

const LinkInfoAttr = @import("attrs/link_info.zig").LinkInfoAttr;

pub const LinkAttribute = union(enum) {
    name: []const u8,
    master: u32,
    link_info: LinkInfoAttr,
    netns_fd: linux.fd_t,

    pub fn size(self: LinkAttribute) usize {
        const val_len = switch (self) {
            .name => |val| val.len + 1,
            .link_info => |val| val.size(),
            .master, .netns_fd => 4,
        };

        return nalign(val_len + @sizeOf(linux.rtattr));
    }

    fn getAttr(self: LinkAttribute) linux.rtattr {
        var attr: linux.rtattr = switch (self) {
            .name => |val| .{ .len = @intCast(val.len + 1), .type = .IFNAME },
            .link_info => |val| .{ .len = @intCast(val.size()), .type = .LINKINFO },
            .master => .{ .len = 4, .type = .MASTER },
            .netns_fd => .{ .len = 4, .type = .NET_NS_FD },
        };

        attr.len = @intCast(std.mem.alignForward(usize, attr.len + @sizeOf(linux.rtattr), 4));
        return attr;
    }

    pub fn encode(self: LinkAttribute, buff: []u8) !usize {
        const header = self.getAttr();
        @memcpy(buff[0..@sizeOf(linux.rtattr)], std.mem.asBytes(&header));
        const len = try self.encodeVal(buff[@sizeOf(linux.rtattr)..]);
        return nalign(len + @sizeOf(linux.rtattr));
    }

    inline fn encodeVal(self: LinkAttribute, buff: []u8) !usize {
        return switch (self) {
            .name => |val| {
                @memcpy(buff[0..val.len], val);
                buff[val.len] = 0;
                return val.len + 1;
            },
            .link_info => |val| try val.encode(buff),
            .master => |val| {
                @memcpy(buff[0..4], std.mem.asBytes(&val));
                return 4;
            },
            .netns_fd => |val| {
                @memcpy(buff[0..4], std.mem.asBytes(&val));
                return 4;
            },
        };
    }
};
