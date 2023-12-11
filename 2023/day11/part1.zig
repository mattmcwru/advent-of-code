const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

const Galaxy = struct {
    x: usize,
    y: usize,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const gpa_status = gpa.deinit();
        if (gpa_status == .leak) expect(false) catch @panic("GPA Leaked Memory");
    }

    const filename = getFileNameFromArgs(allocator) catch return;
    defer allocator.free(filename);

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var galaxy_list = std.ArrayList(Galaxy).init(allocator);
    defer galaxy_list.deinit();

    var line_y: usize = 0;
    var line_x_max: usize = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        print("{s}\n", .{line});

        var galaxy_found = false;

        for (line, 0..) |c, i| {
            if (c == '#') {
                galaxy_found = true;
                try galaxy_list.append(.{ .x = i, .y = line_y });
            }
        }

        // Insert extra row if no galaxy found
        line_y += if (!galaxy_found) 2 else 1;
        line_x_max = @max(line_x_max, line.len);
    }

    // Insert extra columns
    {
        var add_rows: usize = 0;
        var i: usize = line_x_max;
        while (i > 0) {
            i -= 1;
            var galaxy_found = false;

            for (galaxy_list.items) |*item| {
                if (item.x == i) galaxy_found = true;
                if (item.x > i) item.x += add_rows;
            }

            add_rows = if (!galaxy_found) 1 else 0;
        }
    }

    // Measure distances
    var total_distance: usize = 0;
    for (galaxy_list.items, 0..) |g1, i| {
        for (galaxy_list.items[i + 1 ..]) |g2| {
            const distance = abs(g1.x, g2.x) + abs(g1.y, g2.y);
            print("<{},{}> to <{},{}> => {}\n", .{ g1.x, g1.y, g2.x, g2.y, distance });
            total_distance += distance;
        }
    }

    // Print list
    for (galaxy_list.items) |item| {
        print("{}, {}\n", .{ item.x, item.y });
    }

    print("Galaxies found: {}\n", .{galaxy_list.items.len});
    print("Total Distance: {}\n", .{total_distance});
}

pub fn abs(a: usize, b: usize) usize {
    return if (a > b) a - b else b - a;
}
