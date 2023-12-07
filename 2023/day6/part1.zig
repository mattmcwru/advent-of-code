const std = @import("std");
const print = std.debug.print;

fn verifyLabel(label: []const u8, expected: []const u8) bool {
    if (std.mem.eql(u8, label, expected)) {
        return true;
    }
    print("Error: Bad label \"{s}\", expected \"{s}\"\n", .{ label, expected });
    return false;
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
    var time_list = std.ArrayList(u32).init(allocator);
    defer time_list.deinit();

    if (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        print("{s}\n", .{line});
        var time_tok = std.mem.tokenizeScalar(u8, line, ' ');

        // Verify label
        if (time_tok.next()) |label| if (!verifyLabel(label, "Time:")) return;

        while (time_tok.next()) |time| {
            try time_list.append(try std.fmt.parseInt(u32, time, 10));
        }
    }

    var dist_list = std.ArrayList(u32).init(allocator);
    defer dist_list.deinit();

    // Get the Distance input
    if (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        print("{s}\n", .{line});
        var dist_tok = std.mem.tokenizeScalar(u8, line, ' ');

        // Verify label
        if (dist_tok.next()) |label| if (!verifyLabel(label, "Distance:")) return;

        while (dist_tok.next()) |time| {
            try dist_list.append(try std.fmt.parseInt(u32, time, 10));
        }
    }

    var total_wins: ?u32 = null;

    for (time_list.items, dist_list.items, 1..) |time, dist, i| {
        print("Race {}: time {d:2} dist {d:3} ", .{ i, time, dist });

        var wins: u32 = 0;

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
