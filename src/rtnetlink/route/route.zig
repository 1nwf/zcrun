const std = @import("std");
const nalign = @import("../utils.zig").nalign;
const linux = std.os.linux;
const RouteScope = @import("../address/address.zig").AddressScope;
const c = @cImport(@cInclude("linux/rtnetlink.h"));
const Attr = @import("attrs.zig").Attr;

const Flags = enum(u32) {
    // next hop flags
    Dead = c.RTNH_F_DEAD, // Nexthop is dead (used by multipath)
    Pervasive = c.RTNH_F_PERVASIVE, // Do recursive gateway lookup
    Onlink = c.RTNH_F_ONLINK, // Gateway is forced on link
    Offload = c.RTNH_F_OFFLOAD, // Nexthop is offloaded
    Linkdown = c.RTNH_F_LINKDOWN, // carrier-down on nexthop
    Unresolved = c.RTNH_F_UNRESOLVED, // The entry is unresolved (ipmr)
    Trap = c.RTNH_F_TRAP, // Nexthop is trapping packets
    // flags
    Notify = c.RTM_F_NOTIFY, // Notify user of route change
    Cloned = c.RTM_F_CLONED, // This route is cloned
    Equalize = c.RTM_F_EQUALIZE, // Multipath equalizer: NI
    Prefix = c.RTM_F_PREFIX, // Prefix addresses
    LookupTable = c.RTM_F_LOOKUP_TABLE, // set rtm_table to FIB lookup result
    FibMatch = c.RTM_F_FIB_MATCH, // return full fib lookup match
    RtOffload = c.RTM_F_OFFLOAD, // route is offloaded
    RtTrap = c.RTM_F_TRAP, // route is trapping packets
    OffloadFailed = c.RTM_F_OFFLOAD_FAILED,

    _,
};

const RouteType = enum(u8) {
    Unspec = c.RTN_UNSPEC,
    Unicast = c.RTN_UNICAST,
    Local = c.RTN_LOCAL,
    Broadcast = c.RTN_BROADCAST,
    Anycast = c.RTN_ANYCAST,
    Multicast = c.RTN_MULTICAST,
    BlackHole = c.RTN_BLACKHOLE,
    Unreachable = c.RTN_UNREACHABLE,
    Prohibit = c.RTN_PROHIBIT,
    Throw = c.RTN_THROW,
    Nat = c.RTN_NAT,
    ExternalResolve = c.RTN_XRESOLVE,
    _,
};

const Protocol = enum(u8) {
    Unspec = c.RTPROT_UNSPEC,
    IcmpRedirect = c.RTPROT_REDIRECT,
    Kernel = c.RTPROT_KERNEL,
    Boot = c.RTPROT_BOOT,
    Static = c.RTPROT_STATIC,
    Gated = c.RTPROT_GATED,
    Ra = c.RTPROT_RA,
    Mrt = c.RTPROT_MRT,
    Zebra = c.RTPROT_ZEBRA,
    Bird = c.RTPROT_BIRD,
    DnRouted = c.RTPROT_DNROUTED,
    Xorp = c.RTPROT_XORP,
    Ntk = c.RTPROT_NTK,
    Dhcp = c.RTPROT_DHCP,
    Mrouted = c.RTPROT_MROUTED,
    KeepAlived = c.RTPROT_KEEPALIVED,
    Babel = c.RTPROT_BABEL,
    OpenNr = c.RTPROT_OPENR,
    Bgp = c.RTPROT_BGP,
    Isis = c.RTPROT_ISIS,
    Ospf = c.RTPROT_OSPF,
    Rip = c.RTPROT_RIP,
    Eigrp = c.RTPROT_EIGRP,
    _,
};

const RouteTable = enum(u8) {
    Unspec = c.RT_TABLE_UNSPEC,
    Compat = c.RT_TABLE_COMPAT,
    Default = c.RT_TABLE_DEFAULT,
    Main = c.RT_TABLE_MAIN,
    Local = c.RT_TABLE_LOCAL,
};

pub const RouteHeader = extern struct {
    family: u8 = linux.AF.INET,
    dest_prefix_len: u8 = 0,
    src_prefix_len: u8 = 0,
    tos: u8 = 0,
    table: RouteTable = .Main,
    protocol: Protocol = .Unspec,
    scope: RouteScope = .Universe,
    type: RouteType = .Unspec,
    flags: u32 = 0,
};

pub const RouteInfo = struct {
    hdr: RouteHeader,
    attrs: std.ArrayList(Attr),

    pub fn init(allocator: std.mem.Allocator) RouteInfo {
        return .{
            .hdr = .{},
            .attrs = std.ArrayList(Attr).init(allocator),
        };
    }

    pub fn size(self: *const RouteInfo) usize {
        var s: usize = @sizeOf(RouteHeader);
        for (self.attrs.items) |a| {
            s += a.size();
        }
        return nalign(s);
    }

    pub fn encode(self: *const RouteInfo, buff: []u8) !void {
        @memcpy(buff[0..@sizeOf(RouteHeader)], std.mem.asBytes(&self.hdr));
        var start: usize = @sizeOf(RouteHeader);

        for (self.attrs.items) |attr| {
            start += try attr.encode(buff[start..]);
        }
    }
    pub fn deinit(self: *RouteInfo) void {
        self.attrs.deinit();
    }
};

const RequestType = enum {
    create,
    delete,
    get,

    fn toMsgType(self: RequestType) linux.NetlinkMessageType {
        return switch (self) {
            .create => .RTM_NEWROUTE,
            .delete => .RTM_DELROUTE,
            .get => .RTM_GETROUTE,
        };
    }

    fn getFlags(self: RequestType) u16 {
        var flags: u16 = linux.NLM_F_REQUEST | linux.NLM_F_ACK;
        switch (self) {
            .create => flags |= linux.NLM_F_CREATE | linux.NLM_F_EXCL,
            else => {},
        }

        return flags;
    }
};

hdr: linux.nlmsghdr,
msg: RouteInfo,
allocator: std.mem.Allocator,

const Route = @This();
pub fn init(allocator: std.mem.Allocator, req_type: RequestType) Route {
    return .{
        .hdr = .{
            .type = req_type.toMsgType(),
            .flags = req_type.getFlags(),
            .len = 0,
            .pid = 0,
            .seq = 0,
        },
        .msg = RouteInfo.init(allocator),
        .allocator = allocator,
    };
}

pub fn compose(self: *Route) ![]u8 {
    const size: usize = self.msg.size() + @sizeOf(linux.nlmsghdr);

    var buff = try self.allocator.alloc(u8, size);
    self.hdr.len = @intCast(size);

    // copy data into buff
    @memset(buff, 0);
    var start: usize = 0;
    @memcpy(buff[0..@sizeOf(linux.nlmsghdr)], std.mem.asBytes(&self.hdr));
    start += @sizeOf(linux.nlmsghdr);
    try self.msg.encode(buff[start..]);

    return buff;
}

pub fn addAttr(self: *Route, attr: Attr) !void {
    try self.msg.attrs.append(attr);
}

pub fn deinit(self: *Route) void {
    self.msg.deinit();
}
