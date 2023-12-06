const std = @import("std");

pub fn switch_test(line: []const u8) struct { f: bool, v: u8 } {
    return .{ .f = true, .v = line[0] };
}

pub fn main() !void {
    const line = "3d58e47";

    const res = switch_test(line);

    std.debug.print("{} {}\n", .{ res.f, res.v });
}
