const std = @import("std");
const log = std.log;
const linux = std.os.linux;
const utils = @import("utils.zig");
const checkErr = utils.checkErr;
const INFO_PATH = utils.INFO_PATH;
const NETNS_PATH = utils.NETNS_PATH;

const NetLink = @import("rtnetlink/rtnetlink.zig");

nl: NetLink,
allocator: std.mem.Allocator,
const Net = @This();

pub fn init(allocator: std.mem.Allocator) !Net {
    return .{
        .nl = try NetLink.init(allocator),
        .allocator = allocator,
    };
}

pub fn setupContainerNetNs(self: *Net, cid: []const u8) !void {
    const cns_mount = try std.mem.concat(self.allocator, u8, &.{ NETNS_PATH, cid });
    log.info("cns_mount: {s}", .{cns_mount});

    const cns = std.fs.createFileAbsolute(cns_mount, .{ .exclusive = true }) catch |e| {
        if (e != error.PathAlreadyExists) return e;
        const cns = try std.fs.openFileAbsolute(cns_mount, .{});
        defer cns.close();

        return setNetNs(cns.handle);
    };
    defer cns.close();

    try checkErr(linux.unshare(linux.CLONE.NEWNET), error.Unshare);
    try checkErr(linux.mount("/proc/self/ns/net", @ptrCast(cns_mount.ptr), "bind", linux.MS.BIND, 0), error.Mount);

    const self_ns = try std.fs.openFileAbsolute("/proc/self/ns/net", .{});
    defer self_ns.close();

    return setNetNs(self_ns.handle);
}

pub fn setUpBridge(self: *Net) !void {
    if (self.isBridgeUp()) return;
    var la = self.nl.linkAdd(.{ .bridge = utils.BRIDGE_NAME });
    // TODO: get default network interface
    try self.if_enable_snat("eth0");
    try la.exec();
}

fn setNetNs(fd: linux.fd_t) !void {
    const res = linux.syscall2(.setns, @intCast(fd), linux.CLONE.NEWNET);
    try checkErr(res, error.NetNsFailed);
}

fn isBridgeUp(self: *Net) bool {
    var br = self.nl.linkGet(.{ .name = utils.BRIDGE_NAME });
    defer br.msg.deinit();
    _ = br.exec() catch return false;
    return true;
}

fn if_enable_snat(self: *Net, if_name: []const u8) !void {
    var ch = std.ChildProcess.init(&.{ "iptables", "-t", "nat", "-A", "POSTROUTING", "-o", if_name, "-j", "MASQUERADE" }, self.allocator);
    const term = try ch.spawnAndWait();
    if (term.Exited != 0) {
        return error.CmdFailed;
    }
}

pub fn createVethPair(self: *Net, cid: []const u8) !void {
    const veth0 = try std.mem.concat(self.allocator, u8, &.{ "veth0-", cid });
    const veth1 = try std.mem.concat(self.allocator, u8, &.{ "veth1-", cid });

    var lg = self.nl.linkGet(.{ .name = veth0 });
    if (lg.exec()) |_| {
        return; // veth pair exists, so return
    } else |_| {}
    log.info("creating veth pair: {s} -- {s}", .{ veth0, veth1 });

    var la = self.nl.linkAdd(.{ .veth = .{ veth0, veth1 } });
    try la.exec();

    lg = self.nl.linkGet(.{ .name = veth0 });
    const veth0_info = try lg.exec();

    // TODO: use random private ip addrs that are not used
    var a0 = self.nl.addrAdd(.{ .index = veth0_info.msg.header.index, .addr = .{ 10, 0, 0, 1 }, .prefix_len = 24 });
    try a0.exec();

    lg = self.nl.linkGet(.{ .name = veth1 });
    const veth1_info = try lg.exec();

    var a1 = self.nl.addrAdd(.{ .index = veth1_info.msg.header.index, .addr = .{ 10, 0, 0, 2 }, .prefix_len = 24 });
    try a1.exec();
}
