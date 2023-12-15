const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

const MirrorMap = struct {
    map: [64][64]u8,
    map_width: usize,
    map_lines: usize,
};

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

    var mirror_map = MirrorMap{
        .map = .{.{0} ** 64} ** 64,
        .map_width = 0,
        .map_lines = 0,
    };

    var total_sum: usize = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    var eof: bool = false;
    while (!eof) {
        while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            if (line.len == 0) break; // Blank line between groups
            print("{s}\n", .{line});
            try expect(line.len < 64 and mirror_map.map_lines < 63);

            for (line, 0..) |c, i| {
                mirror_map.map[mirror_map.map_lines][i] = c;
            }
            mirror_map.map_lines += 1;
            mirror_map.map_width = @max(mirror_map.map_width, line.len);
        } else {
            eof = true; // EOF
        }

        var map_sum: usize = 0;

        // Search map for vertical row mirror
        var row_mirror_at: ?usize = null;
        var row_mirror_found: bool = false;

        for (0..mirror_map.map_width - 1) |col| {
            // test first row for match
            if (mirror_map.map[0][col] != mirror_map.map[0][col + 1]) {
                continue;
            }
            // verify remaining column
            for (0..mirror_map.map_lines) |row| {
                if (!isRowMirror(&mirror_map, col, row)) break;
            } else {
                print("Row mirror found at {}\n", .{col});
                row_mirror_at = col;
                row_mirror_found = true;
                map_sum = col + 1;
                break;
            }
        } else {
            print("No row mirror found\n", .{});
        }

        // Search map for vertical row mirror
        var col_mirror_at: ?usize = null;
        var col_mirror_found: bool = false;
        for (0..mirror_map.map_lines - 1) |row| {
            // test first row for match
            if (mirror_map.map[row][0] != mirror_map.map[row + 1][0]) {
                continue;
            }
            // verify remaining column
            for (0..mirror_map.map_width) |col| {
                if (!isColMirror(&mirror_map, row, col)) break;
            } else {
                print("Col mirror found at {}\n", .{row});
                col_mirror_at = row;
                col_mirror_found = true;
                map_sum += 100 * (row + 1);
                break;
            }
        } else {
            print("No col mirror found\n", .{});
        }

        // Reset map
        mirror_map.map_width = 0;
        mirror_map.map_lines = 0;

        total_sum += map_sum;

        print("Sum: {}\n\n", .{map_sum});
    }

    print("Total Sum: {}\n", .{total_sum});
}

// check mirror across vertical column
pub fn isColMirror(map: *const MirrorMap, split_at: usize, col: usize) bool {
    if (split_at > map.map_lines - 2) return false;

    for (0..@min(split_at + 1, map.map_lines - (split_at + 1))) |i| {
        //print("{} {} {c} == {c} ", .{ split_at - i, split_at + 1 + i, map.map[row][split_at - i], map.map[row][split_at + 1 + i] });
        if (map.map[split_at - i][col] != map.map[split_at + 1 + i][col]) {
            //print("false\n", .{});
            return false;
        } //else print("true\n", .{});
    } else {
        return true;
    }
}

// check mirror across horizontal row
pub fn isRowMirror(map: *const MirrorMap, split_at: usize, row: usize) bool {
    if (split_at > map.map_width - 2) return false;

    for (0..@min(split_at + 1, map.map_width - (split_at + 1))) |i| {
        //print("{} {} {c} == {c} ", .{ split_at - i, split_at + 1 + i, map.map[row][split_at - i], map.map[row][split_at + 1 + i] });
        if (map.map[row][split_at - i] != map.map[row][split_at + 1 + i]) {
            //print("false\n", .{});
            return false;
        } //else print("true\n", .{});
    } else {
        return true;
    }
}

test "isRowMirror" {
    var map = MirrorMap{
        .map = .{.{0} ** 64} ** 64,
        .map_width = 0,
        .map_lines = 0,
    };

    const test_line = ".#..##..#";

    for (test_line, 0..) |c, i| {
        map.map[0][i] = c;
        map.map_width += 1;
    }
    map.map_lines = 1;

    try expect(isRowMirror(&map, 4, 0) == true);
    try expect(isRowMirror(&map, 3, 0) == false);
}
