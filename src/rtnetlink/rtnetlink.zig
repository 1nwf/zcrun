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
    switch (linux.getErrno(res)) {
        .SUCCESS => {},
        else => return error.BindFailed,
    }

    return .{ .allocator = allocator, .fd = fd };
}

pub fn deinit(self: *Self) void {
    std.os.close(self.fd);
}

pub fn exec(self: *Self, msg: []u8) !void {
    std.debug.assert(try std.os.send(self.fd, msg, 0) == msg.len);
    try self.recv();
}

fn recv(self: *Self) !void {
    var buff: [512]u8 = std.mem.zeroes([512]u8);
    const n = try std.os.recv(self.fd, &buff, 0);
    // log.info("n: {}", .{n});
    // log.info("buff: {any}", .{buff[0..n]});

    const header = std.mem.bytesAsValue(linux.nlmsghdr, buff[0..@sizeOf(linux.nlmsghdr)]);
    // log.info("header: {}", .{header});
    if (header.type == .DONE) {
        return;
    } else if (header.type == .ERROR) {
        return error.Error;
    }

    var start: usize = @sizeOf(linux.nlmsghdr);
    // const link = std.mem.bytesAsValue(linux.ifinfomsg, buff[start .. start + @sizeOf(linux.ifinfomsg)]);
    // log.info("link: {}", .{link});

    start += @sizeOf(linux.ifinfomsg);

    while (start < n) {
        const attr = std.mem.bytesAsValue(linux.rtattr, buff[start .. start + @sizeOf(linux.rtattr)]);
        switch (attr.type) {
            .IFNAME => {
                const name: []u8 = @ptrCast(buff[start + @sizeOf(linux.rtattr) .. start + attr.len]);
                log.info("name is: {s}", .{name});
                break;
            },
            else => {},
        }
        start += attr.len;
    }

    try self.recv();
}
