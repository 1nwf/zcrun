const std = @import("std");
const log = std.log;
const linux = std.os.linux;
const utils = @import("utils.zig");
const checkErr = utils.checkErr;
const INFO_PATH = utils.INFO_PATH;
const NETNS_PATH = utils.NETNS_PATH;
const ip = @import("ip.zig");

const NetLink = @import("rtnetlink/rtnetlink.zig");

cid: []const u8,
nl: NetLink,
allocator: std.mem.Allocator,
const Net = @This();

pub fn init(allocator: std.mem.Allocator, cid: []const u8) !Net {
    return .{
        .cid = cid,
        .nl = try NetLink.init(allocator),
        .allocator = allocator,
    };
}

pub fn setupContainerNetNs(self: *Net) !void {
    const cns_mount = try std.mem.concat(self.allocator, u8, &.{ NETNS_PATH, self.cid });
    defer self.allocator.free(cns_mount);
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
    if (self.linkExists(utils.BRIDGE_NAME)) return;
    try self.nl.linkAdd(.{ .bridge = utils.BRIDGE_NAME });

    var bridge = try self.nl.linkGet(.{ .name = utils.BRIDGE_NAME });
    defer bridge.deinit();
    try self.nl.linkSet(.{ .index = bridge.msg.header.index, .up = true });
    try self.nl.addrAdd(.{ .index = bridge.msg.header.index, .addr = .{ 10, 0, 0, 1 }, .prefix_len = 24 }); //
}

fn setNetNs(fd: linux.fd_t) !void {
    const res = linux.syscall2(.setns, @intCast(fd), linux.CLONE.NEWNET);
    try checkErr(res, error.NetNsFailed);
}

/// enables snat on default interface
/// this allows containers to access the internet
pub fn enableNat(self: *Net) !void {
    const default_ifname = try self.getDefaultGatewayIfName();
    try self.if_enable_snat(default_ifname);
}

fn getDefaultGatewayIfName(self: *Net) ![]const u8 {
    const res = try self.nl.routeGet();
    var if_index: ?u32 = null;
    var has_gtw = false;
    for (res) |*msg| {
        defer msg.deinit();
        if (has_gtw) continue;
        for (msg.msg.attrs.items) |attr| {
            switch (attr) {
                .gateway => has_gtw = true,
                .output_if => |val| if_index = val,
            }
        }
    }
    const idx = if_index orelse return error.NotFound;
    var if_info = try self.nl.linkGet(.{ .index = idx });
    defer if_info.deinit();
    var name: ?[]const u8 = null;
    for (if_info.msg.attrs.items) |attr| {
        switch (attr) {
            .name => |val| {
                name = val;
                break;
            },
            else => {},
        }
    }

    return name orelse error.NotFound;
}

fn if_enable_snat(self: *Net, if_name: []const u8) !void {
    var check_rule = std.ChildProcess.init(&.{ "iptables", "-t", "nat", "-C", "POSTROUTING", "-o", if_name, "-j", "MASQUERADE" }, self.allocator);
    check_rule.stdout_behavior = .Ignore;
    check_rule.stderr_behavior = .Ignore;
    const check_rule_res = try check_rule.spawnAndWait();
    if (check_rule_res.Exited == 0) return;

    // add rule if it doesn't exist
    var ch = std.ChildProcess.init(&.{ "iptables", "-t", "nat", "-A", "POSTROUTING", "-o", if_name, "-j", "MASQUERADE" }, self.allocator);
    ch.stdout_behavior = .Ignore;
    ch.stderr_behavior = .Ignore;
    const term = try ch.spawnAndWait();
    if (term.Exited != 0) {
        return error.CmdFailed;
    }
}

pub fn createVethPair(self: *Net) !void {
    const veth0 = try std.mem.concat(self.allocator, u8, &.{ "veth0-", self.cid });
    const veth1 = try std.mem.concat(self.allocator, u8, &.{ "veth1-", self.cid });
    defer {
        self.allocator.free(veth0);
        self.allocator.free(veth1);
    }

    if (self.linkExists(veth0)) return;
    log.info("creating veth pair: {s} -- {s}", .{ veth0, veth1 });

    try self.nl.linkAdd(.{ .veth = .{ veth0, veth1 } });

    var veth0_info = try self.nl.linkGet(.{ .name = veth0 });
    defer veth0_info.deinit();

    // attach veth0 to host bridge
    var bridge = try self.nl.linkGet(.{ .name = utils.BRIDGE_NAME });
    defer bridge.deinit();
    try self.nl.linkSet(.{ .index = veth0_info.msg.header.index, .master = bridge.msg.header.index, .up = true });

    var veth1_info = try self.nl.linkGet(.{ .name = veth1 });
    defer veth1_info.deinit();

    // move other veth interface to container netns
    const cns_mount = try std.mem.concat(self.allocator, u8, &.{ NETNS_PATH, self.cid });
    const netns = try std.fs.openFileAbsolute(cns_mount, .{});
    defer {
        self.allocator.free(cns_mount);
        netns.close();
    }
    try self.nl.linkSet(.{ .index = veth1_info.msg.header.index, .netns_fd = netns.handle });

    try setNetNs(netns.handle);
    // create new rtnetlink conn in netns
    var nl = try NetLink.init(self.allocator);
    defer nl.deinit();
    var cveth1_info = try nl.linkGet(.{ .name = veth1 });
    defer cveth1_info.deinit();

    try nl.linkSet(.{ .index = cveth1_info.msg.header.index, .up = true });
    // TODO: use random private ip addrs that are not used
    try nl.addrAdd(.{ .index = cveth1_info.msg.header.index, .addr = ip.getRandomIpv4Addr(), .prefix_len = 24 });
    try nl.routeAdd(.{ .gateway = .{ 10, 0, 0, 1 } });

    // setup container loopback interface
    var lo = try nl.linkGet(.{ .name = "lo" });
    defer lo.deinit();

    nl.addrAdd(.{ .index = lo.msg.header.index, .addr = .{ 127, 0, 0, 1 }, .prefix_len = 8 }) catch |e| {
        if (e != error.Exists) return e;
    };
    try nl.linkSet(.{ .index = lo.msg.header.index, .up = true });
}

fn linkExists(self: *Net, name: []const u8) bool {
    var info = self.nl.linkGet(.{ .name = name }) catch return false;
    defer info.deinit();
    return true;
}

pub fn setupDnsResolverConfig(_: *Net, rootfs: []const u8) !void {
    var rootfs_dir = try std.fs.cwd().openDir(rootfs, .{});
    var etc_dir = try std.fs.cwd().openDir("/etc", .{});
    defer rootfs_dir.close();
    defer etc_dir.close();

    try etc_dir.copyFile("resolv.conf", rootfs_dir, "etc/resolv.conf", .{});
}

pub fn deinit(self: *Net) !void {
    // delete created veth pairs
    // deleting one will automatically remove the other
    const veth0_name = try std.mem.concat(self.allocator, u8, &.{ "veth0-", self.cid });
    defer self.allocator.free(veth0_name);
    var veth0 = try self.nl.linkGet(.{ .name = veth0_name });
    defer veth0.deinit();
    try self.nl.linkDel(veth0.msg.header.index);

    self.nl.deinit();
}
