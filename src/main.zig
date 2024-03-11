const std = @import("std");
const log = std.log;
const linux = std.os.linux;
const Net = @import("net.zig");
const Container = @import("container.zig");
const args = @import("args.zig");

const utils = @import("utils.zig");
const checkErr = utils.checkErr;

pub fn main() !void {
    const cmd = try args.parseArgs(std.heap.page_allocator);
    switch (cmd) {
        .run => |r| {
            var container = try Container.init(r.rootfs_path, r.cmd, std.heap.page_allocator);
            try container.run();
        },
        .help => {
            _ = try std.io.getStdOut().write(args.help);
        },
    }
}
