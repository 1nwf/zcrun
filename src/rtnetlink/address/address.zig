const std = @import("std");
const linux = std.os.linux;
const nalign = @import("../utils.zig").nalign;
const c = @cImport(@cInclude("linux/rtnetlink.h"));
const AddressAttr = @import("attrs.zig").AddressAttr;

pub const AddressScope = enum(u8) {
    Universe = c.RT_SCOPE_UNIVERSE,
    Site = c.RT_SCOPE_SITE,
    Link = c.RT_SCOPE_LINK,
    Host = c.RT_SCOPE_HOST,
    Nowhere = c.RT_SCOPE_NOWHERE,
    _,
};

const AddressHeader = packed struct {
    family: u8,
    prefix_len: u8,
    flags: u8,
    scope: AddressScope,
    index: u32,
};

pub const AddressInfo = struct {
    hdr: AddressHeader,
    attrs: std.ArrayList(AddressAttr),
    pub fn init(allocator: std.mem.Allocator) AddressInfo {
        return .{
            .hdr = .{
                .family = linux.AF.INET,
                .prefix_len = 0,
                .flags = 0,
                .scope = .Universe,
                .index = 0,
            },
            .attrs = std.ArrayList(AddressAttr).init(allocator),
        };
    }

    pub fn size(self: *const AddressInfo) usize {
        var s: usize = @sizeOf(AddressHeader);
        for (self.attrs.items) |a| {
            s += a.size();
        }
        return nalign(s);
    }

    pub fn encode(self: *const AddressInfo, buff: []u8) !void {
        var start: usize = 0;
        @memcpy(buff[start .. start + @sizeOf(AddressHeader)], std.mem.asBytes(&self.hdr));
        start += @sizeOf(AddressHeader);

        for (self.attrs.items) |attr| {
            start += try attr.encode(buff[start..]);
        }
    }
};

const RequestType = enum {
    create,
    delete,
    get,

    fn toMsgType(self: RequestType) linux.NetlinkMessageType {
        return switch (self) {
            .create => .RTM_NEWADDR,
            .delete => .RTM_DELADDR,
            .get => .RTM_GETADDR,
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

const Addr = @This();

hdr: linux.nlmsghdr,
msg: AddressInfo,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, req_type: RequestType) Addr {
    return .{
        .hdr = .{
            .type = req_type.toMsgType(),
            .flags = req_type.getFlags(),
            .len = 0,
            .pid = 0,
            .seq = 0,
        },
        .msg = AddressInfo.init(allocator),
        .allocator = allocator,
    };
}

pub fn compose(self: *Addr) ![]u8 {
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

pub fn addAttr(self: *Addr, attr: AddressAttr) !void {
    try self.msg.attrs.append(attr);
}
