const std = @import("std");
const print = std.debug.print;

fn verifyLabel(label: []const u8, expected: []const u8) bool {
    if (std.mem.eql(u8, label, expected)) {
        return true;
    }
    print("Error: Bad label \"{s}\", expected \"{s}\"\n", .{ label, expected });
    return false;
}

// Shift items matching needle to the right and returns size of non-needle items
// WARNING: Returned buffer must be deallocated by caller!
fn trimAll(allocator: std.mem.Allocator, comptime T: type, needle: T, haystack: []const T) ![]const T {
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
        if (haystack[head] != needle and head > tail) {
            buf[tail] = haystack[head];
            tail += 1;
        }
    }
    return buf;
}

test "trimAll testing" {
    const test_string = "   this is a test string    with    spaces  ";

    const trim_string = try trimAll(std.testing.allocator, u8, ' ', test_string);
    defer std.testing.allocator.free(trim_string);

    print("size = {}: [{s}]\n", .{ trim_string.len, trim_string });
}

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    const filename = getFileNameFromArgs(allocator) catch return;
    defer allocator.free(filename);

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    // Collect all data from input file
    var buf: [1024]u8 = undefined;

    // Get the Time input
    var time_list = std.ArrayList(u64).init(allocator);
    defer time_list.deinit();

    if (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        print("{s} | ", .{line});

        const time = try trimAll(allocator, u8, ' ', line[5..]);
        defer allocator.free(time);

        print("{s}\n", .{time});
        try time_list.append(try std.fmt.parseInt(u64, time, 10));
    }

    var dist_list = std.ArrayList(u64).init(allocator);
    defer dist_list.deinit();

    // Get the Distance input
    if (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        print("{s} | ", .{line});

        const dist = try trimAll(allocator, u8, ' ', line[9..]);
        defer allocator.free(dist);

        print("{s}\n", .{dist});
        try dist_list.append(try std.fmt.parseInt(u64, dist, 10));
    }

    var total_wins: ?u64 = null;

    for (time_list.items, dist_list.items, 1..) |time, dist, i| {
        print("Race {}: time {d:2} dist {d:3} ", .{ i, time, dist });

        var wins: u64 = 0;

        for (1..time) |t| {
            if (t * (time - t) > dist) wins += 1;
        }
        print("wins {}\n", .{wins});
        total_wins = if (total_wins) |tw| tw * wins else wins;
    }

    print("Total Wins: {}\n", .{total_wins.?});
}

// Must free returned string
fn getFileNameFromArgs(allocator: std.mem.Allocator) ![]u8 {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Error: Missing file argument\n\n", .{});
        std.debug.print("Usage: zig run part1.zig -- <filename>\n", .{});
        return error.FileNotFound;
    }

    const filename = try allocator.alloc(u8, args[1].len);
    errdefer allocator.free(filename);

    std.mem.copy(u8, filename, args[1]);

    return filename;
}
