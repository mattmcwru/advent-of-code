const std = @import("std");
const expect = std.testing.expect;

//
// Trim all items matching needle from the input buffer and return a new buffer of correct length.
//
// WARNING: Returned buffer must be deallocated by caller!
//
pub fn trimAll(allocator: std.mem.Allocator, comptime T: type, needle: T, haystack: []const T) ![]const T {

    // Find size required for return buffer
    var needles: usize = 0;
    for (haystack) |i| {
        if (i == needle)
            needles += 1;
    }

    // Allocate return buffer (this must be deallocated by caller)
    var buf = try allocator.alloc(T, haystack.len - needles);
    errdefer allocator.free(buf);

    // Move non-needles to return buffer
    var head: usize = 0;
    var tail: usize = 0;
    while (head < haystack.len) : (head += 1) {
        if (haystack[head] != needle) {
            buf[tail] = haystack[head];
            tail += 1;
        }
    }
    return buf;
}

test "trimAll testing" {
    const allocator = std.testing.allocator;

    const test_pair = struct { in: []const u8, exp: []const u8 };
    const test_strings = [_]test_pair{
        .{ .in = "   this is a test string    with    spaces  ", .exp = "thisisateststringwithspaces" },
        .{ .in = "another        test       string       with        a      lot      more         spaces", .exp = "anotherteststringwithalotmorespaces" },
        .{ .in = "teststringwithoutanyspaces", .exp = "teststringwithoutanyspaces" },
    };

    std.debug.print("\n", .{});

    for (test_strings, 1..) |s, i| {
        const trim_string = try trimAll(allocator, u8, ' ', s.in);
        defer allocator.free(trim_string);
        std.debug.print("  test {d}: size = {}: [{s}]", .{ i, trim_string.len, trim_string });
        try expect(std.mem.eql(u8, s.exp, trim_string));
        std.debug.print(" passed\n", .{});
    }
}
