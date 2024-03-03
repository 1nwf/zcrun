const std = @import("std");
const linux = std.os.linux;
const netlink = @import("netlink.zig");

const Self = @This();

const Attr = struct {
    attr: linux.rtattr,
    value: union(enum) {
        name: []const u8,
    },

    fn size(self: *const Attr) usize {
        const value_size = switch (self.value) {
            .name => |v| v.len,
        };
        return @sizeOf(linux.rtattr) + value_size;
    }
};

fd: std.os.socket_t,
allocator: std.mem.Allocator,
msg: linux.ifinfomsg = std.mem.zeroes(linux.ifinfomsg),
attrs: std.ArrayList(Attr),

pub fn init(allocator: std.mem.Allocator) Self {
    const fd: i32 = @intCast(linux.socket(linux.AF.NETLINK, linux.SOCK.RAW, linux.NETLINK.ROUTE));
    const kernel_addr = linux.sockaddr.nl{ .pid = 0, .groups = 0 };
    _ = linux.bind(fd, @ptrCast(&kernel_addr), @sizeOf(@TypeOf(kernel_addr)));
    return .{
        .allocator = allocator,
        .fd = fd,
        .attrs = std.ArrayList(Attr).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    std.os.close(self.fd);
    self.attrs.deinit();
}

pub fn exec(self: *Self) !void {
    var size: usize = @sizeOf(linux.ifinfomsg) + @sizeOf(linux.nlmsghdr);
    for (self.attrs.items) |a| {
        size += a.size();
    }
    size = std.mem.alignForward(usize, size, 4);
    const hdr = linux.nlmsghdr{
        .len = @intCast(size),
        .flags = linux.NLM_F_REQUEST,
        .seq = 0,
        .type = .RTM_NEWLINK,
        .pid = 0,
    };

    var buff = try self.allocator.alloc(u8, size);
    @memset(buff, 0);
    var start: usize = 0;
    @memcpy(buff[0..@sizeOf(linux.nlmsghdr)], std.mem.asBytes(&hdr));
    start += @sizeOf(linux.nlmsghdr);
    @memcpy(buff[start .. start + @sizeOf(linux.ifinfomsg)], std.mem.asBytes(&self.msg));
    start += @sizeOf(linux.ifinfomsg);
    for (self.attrs.items) |attr| {
        @memcpy(buff[start .. start + @sizeOf(linux.rtattr)], std.mem.asBytes(&attr.attr));
        start += @sizeOf(linux.rtattr);
        switch (attr.value) {
            .name => |n| {
                @memcpy(buff[start .. start + n.len], n);
                start += n.len;
            },
        }
    }

    std.debug.assert(try std.os.send(self.fd, buff, 0) == buff.len);
}

pub fn addAttr(self: *Self, attr: Attr) !void {
    try self.attrs.append(attr);
}
