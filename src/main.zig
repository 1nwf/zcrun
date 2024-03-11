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
            try zcrunInit();
            var container = try Container.init(r.name, r.rootfs_path, r.cmd, std.heap.page_allocator);
            try container.run();
        },
        .help => {
            _ = try std.io.getStdOut().write(args.help);
        },
    }
}

pub fn zcrunInit() !void {
    _ = try utils.createDirIfNotExists("/var/run/zcrun");
    _ = try utils.createDirIfNotExists("/var/run/zcrun/containers");
    _ = try utils.createDirIfNotExists("/var/run/zcrun/containers/netns");
    const path = utils.CGROUP_PATH ++ "zcrun/";
    if (!try utils.createDirIfNotExists(path)) return;

    // setup root cgroup
    const root_cgroup = path ++ "cgroup.subtree_control";
    var root_cgroup_file = try std.fs.openFileAbsolute(root_cgroup, .{ .mode = .write_only });
    defer root_cgroup_file.close();
    _ = try root_cgroup_file.write("+cpu +memory +pids"); // enable cpu, mem, and pid controllers in the root cgroup

}
