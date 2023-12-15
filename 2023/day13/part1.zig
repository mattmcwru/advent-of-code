const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

const MapType = std.ArrayList(u64);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() == .leak) expect(false) catch @panic("GPA Leaked Memory");

    const filename = getFileNameFromArgs(allocator) catch return;
    defer allocator.free(filename);

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var map = MapType.init(allocator);
    defer map.deinit();
    var map_width: usize = 0;

    var total_sum: usize = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    var eof: bool = false;

    while (!eof) {
        while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            if (line.len == 0) break; // Blank line between groups
            try expect(line.len < 64);

            var line_bits: u64 = 0;
            for (line) |c| {
                line_bits = (line_bits << 1) | switch (c) {
                    '.' => @as(u64, 0),
                    '#' => @as(u64, 1),
                    else => return error.BadSymbol,
                };
            }
            print("{s} {x:4}\n", .{ line, line_bits });
            try map.append(line_bits);
            map_width = @max(map_width, line.len);
        } else {
            eof = true; // EOF
        }

        var map_sum: usize = 0;

        // Transpose the map
        var t_map = try transposeMap(allocator, &map, map_width);
        defer t_map.deinit();

        // Find the mirrors
        const row_mirror_at = findMirror(&map);
        const col_mirror_at = findMirror(&t_map);

        // Add up the sums
        if (row_mirror_at) |row| {
            map_sum += 100 * row;
            print("Row mirror at {}\n", .{row});
        } else {
            print("Row mirror not found\n", .{});
        }

        if (col_mirror_at) |col| {
            map_sum += col;
            print("Col mirror at {}\n", .{col});
        } else {
            print("Col mirror not found\n", .{});
        }

        total_sum += map_sum;
        print("Sum: {}\n\n", .{map_sum});

        // Clear map for next loop
        map.clearRetainingCapacity();
        map_width = 0;
    }

    print("Total Sum: {}\n", .{total_sum});
}

pub fn findMirror(map: *const MapType) ?usize {
    for (1..map.*.items.len) |n| {
        var mirror_found: bool = true;
        const s = if (map.*.items.len - n > n) 0 else n - (map.*.items.len - n);
        for (s..n) |i| {
            var j = 2 * n - 1 - i;
            //print("{} {} {} & {} : {x} == {x} is ", .{ s, n, i, j, map.*.items[i], map.*.items[j] });
            if (map.*.items[i] != map.*.items[j]) {
                mirror_found = false;
                //print("false\n", .{});
                break;
            } else {
                //print("true\n", .{});
            }
        }
        //print("---\n", .{});
        if (mirror_found)
            return n;
    }
    return null;
}

pub fn transposeMap(allocator: std.mem.Allocator, map: *const MapType, used_width: usize) !MapType {
    try expect(used_width < 64);

    var new_map = MapType.init(allocator);
    try new_map.appendNTimes(0, used_width);

    for (map.items) |d| {
        var shift_d = d;
        var i: usize = new_map.items.len;
        while (i > 0) {
            i -= 1;
            new_map.items[i] = (new_map.items[i] << 1) | (shift_d & 1);
            shift_d >>= 1;
        }
    }
    return new_map;
}
