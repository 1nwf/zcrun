const std = @import("std");

pub fn nalign(value: usize) usize {
    return std.mem.alignForward(usize, value, 4);
}
