const std = @import("std");
const log = std.log;
const linux = std.os.linux;
const link = @import("link.zig");
const addr = @import("address.zig");
const route = @import("route.zig");

const Self = @This();

fd: std.posix.socket_t,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !Self {
    const fd: i32 = @intCast(linux.socket(linux.AF.NETLINK, linux.SOCK.RAW, linux.NETLINK.ROUTE));
    const kernel_addr = linux.sockaddr.nl{ .pid = 0, .groups = 0 };
    const res = linux.bind(fd, @ptrCast(&kernel_addr), @sizeOf(@TypeOf(kernel_addr)));
    if (std.posix.errno(res) != .SUCCESS) {
        return error.BindFailed;
    }

    return .{ .allocator = allocator, .fd = fd };
}

pub fn deinit(self: *Self) void {
    std.posix.close(self.fd);
}

pub fn send(self: *Self, msg: []const u8) !void {
    std.debug.assert(try std.posix.send(self.fd, msg, 0) == msg.len);
}

pub fn recv(self: *Self, buff: []u8) !usize {
    const n = try std.posix.recv(self.fd, buff, 0);
    if (n == 0) {
        return error.InvalidResponse;
    }
    return n;
}

pub fn recv_ack(self: *Self) !void {
    var buff: [512]u8 = std.mem.zeroes([512]u8);
    const n = try std.posix.recv(self.fd, &buff, 0);
    if (n == 0) {
        return error.InvalidResponse;
    }

    const header = std.mem.bytesAsValue(linux.nlmsghdr, buff[0..@sizeOf(linux.nlmsghdr)]);
    if (header.type == .DONE) {
        return;
    } else if (header.type == .ERROR) { // ACK/NACK response
        const response = std.mem.bytesAsValue(NlMsgError, buff[0..]);
        return handle_ack(response.*);
    }
}

pub const NlMsgError = struct {
    hdr: linux.nlmsghdr,
    err: i32,
    msg: linux.nlmsghdr,
};

pub fn handle_ack(msg: NlMsgError) !void {
    const code: linux.E = @enumFromInt(-1 * msg.err);
    if (code != .SUCCESS) {
        log.info("err: {}", .{code});
        return switch (code) {
            .EXIST => error.Exists,
            else => error.Error,
        };
    }
}

pub fn linkAdd(self: *Self, options: link.LinkAdd.Options) !void {
    var la = link.LinkAdd.init(self.allocator, self, options);
    defer la.msg.deinit();
    return la.exec();
}

pub fn linkGet(self: *Self, options: link.LinkGet.Options) !link.LinkMessage {
    var lg = link.LinkGet.init(self.allocator, self, options);
    defer lg.msg.deinit();
    return lg.exec();
}

pub fn linkSet(self: *Self, options: link.LinkSet.Options) !void {
    var ls = link.LinkSet.init(self.allocator, self, options);
    defer ls.msg.deinit();
    try ls.exec();
}

pub fn linkDel(self: *Self, index: c_int) !void {
    var ls = link.LinkDelete.init(self.allocator, self, index);
    defer ls.msg.deinit();
    try ls.exec();
}

pub fn addrAdd(self: *Self, options: addr.AddrAdd.Options) !void {
    var a = addr.AddrAdd.init(self.allocator, self, options);
    return a.exec();
}

pub fn routeAdd(self: *Self, options: route.RouteAdd.Options) !void {
    var ls = route.RouteAdd.init(self.allocator, self, options);
    defer ls.msg.deinit();
    try ls.exec();
}

/// get all ipv4 routes
pub fn routeGet(self: *Self) ![]route.RouteMessage {
    var ls = route.RouteGet.init(self.allocator, self);
    defer ls.msg.deinit();
    return ls.exec();
}
