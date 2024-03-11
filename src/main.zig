const std = @import("std");
const log = std.log;
const linux = std.os.linux;
const Net = @import("net.zig");
const Container = @import("container.zig");

const utils = @import("utils.zig");
const checkErr = utils.checkErr;

pub fn main() !void {
    const args = std.os.argv;
    if (args.len < 3) {
        log.info("invalid args", .{});
        return;
    }

    const rootfs = std.mem.span(args[1]);
    const cmd = std.mem.span(args[2]);

    var container = try Container.init(rootfs, cmd, std.heap.page_allocator);
    try container.run();
}
