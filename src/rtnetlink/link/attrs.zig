const std = @import("std");
const linux = std.os.linux;
const link = @import("link.zig");

const LinkInfoAttr = @import("attrs/link_info.zig").LinkInfoAttr;

pub const LinkAttribute = union(enum) {
    name: []const u8,
    link_info: LinkInfoAttr,

    pub fn size(self: LinkAttribute) usize {
        const val_len = switch (self) {
            .name => |val| val.len + 1,
            .link_info => |val| val.size(),
        };

        return std.mem.alignForward(usize, val_len + @sizeOf(linux.rtattr), 4);
    }

    fn getAttr(self: LinkAttribute) linux.rtattr {
        var attr: linux.rtattr = switch (self) {
            .name => |val| .{ .len = @intCast(val.len + 1), .type = .IFNAME },
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
            .link_info => |val| try val.encode(buff),
        };
    }
};
