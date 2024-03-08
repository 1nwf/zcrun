const std = @import("std");
const log = std.log;
const linux = std.os.linux;

const Self = @This();

fd: std.os.socket_t,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !Self {
    const fd: i32 = @intCast(linux.socket(linux.AF.NETLINK, linux.SOCK.RAW, linux.NETLINK.ROUTE));
    const kernel_addr = linux.sockaddr.nl{ .pid = 0, .groups = 0 };
    const res = linux.bind(fd, @ptrCast(&kernel_addr), @sizeOf(@TypeOf(kernel_addr)));
    if (linux.getErrno(res) != .SUCCESS) {
        return error.BindFailed;
    }

    return .{ .allocator = allocator, .fd = fd };
}

pub fn deinit(self: *Self) void {
    std.os.close(self.fd);
}

pub fn send(self: *Self, msg: []const u8) !void {
    std.debug.assert(try std.os.send(self.fd, msg, 0) == msg.len);
}

pub fn recv(self: *Self, buff: []u8) !usize {
    const n = try std.os.recv(self.fd, buff, 0);
    if (n == 0) {
        return error.InvalidResponse;
    }
    return n;
}

pub fn recv_ack(self: *Self) !void {
    var buff: [512]u8 = std.mem.zeroes([512]u8);
    const n = try std.os.recv(self.fd, &buff, 0);
    if (n == 0) {
        return error.InvalidResponse;
    }

    const header = std.mem.bytesAsValue(linux.nlmsghdr, buff[0..@sizeOf(linux.nlmsghdr)]);
    log.info("header: {}", .{header});
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
        return error.Error;
    }
}
