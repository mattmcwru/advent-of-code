const std = @import("std");
const expect = std.testing.expect;

fn getPri(char: u8) u32 {
    return switch (char) {
        'a'...'z' => 1 + char - 'a',
        'A'...'Z' => 27 + char - 'A',
        else => 0,
    };
}

pub fn main() !void {
    const test_str = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    for (test_str) |c| {
        std.debug.print("{c} {any:2}\n", .{ c, getPri(c) });
    }
}

test "pri test" {
    const test_good = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const test_bad = "0123456789";

    for (test_good, 0..) |c, i| {
        try expect(getPri(c) == i + 1);
    }

    for (test_bad) |c| {
        try expect(getPri(c) == 0);
    }
}
