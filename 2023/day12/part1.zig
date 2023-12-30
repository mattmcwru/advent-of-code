const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

pub fn findArrangements(damaged_list: *[]u8, correct_list: []const u32) !usize {
    var state: enum { on_marker, on_gap } = .on_gap;
    var marker_count: usize = 0;
    var marker_group: usize = 0;

    // Verify line one symbol at a time, if an unknown is found recursively test both options
    for (damaged_list.*, 0..) |item, i| {
        switch (item) {
            '?' => {
                const test_list = [_]u8{ '.', '#' };
                var anum: usize = 0;
                for (test_list) |marker| {
                    damaged_list.*[i] = marker;
                    anum += try findArrangements(damaged_list, correct_list);
                }
                damaged_list.*[i] = '?';
                return anum;
            },
            '#' => {
                marker_count = if (state == .on_gap) 1 else marker_count + 1;
                if (marker_group >= correct_list.len or marker_count > correct_list[marker_group]) return 0; // Markers in group too many
                state = .on_marker;
            },
            '.' => {
                if (state == .on_marker) {
                    if (marker_group >= correct_list.len or marker_count != correct_list[marker_group]) return 0; // Marker number differs
                    marker_group += 1;
                }
                state = .on_gap;
            },
            else => return error.BadSymbolInput,
        }
    } else {
        // No unknown markers found
        if (state == .on_marker) {
            if (marker_group >= correct_list.len or marker_count != correct_list[marker_group]) return 0; // Marker number differs
            marker_group += 1;
        }
        if (marker_group != correct_list.len) return 0; // Number of marker groups and corrects differ

        return 1; // Good arrangement found
    }
}

test "findArrangements" {
    const allocator = std.testing.allocator;

    {
        const damaged_line = "???.###";
        const correct_list = [_]u32{ 1, 1, 3 };
        const expected = 1;

        var mod_line = try allocator.dupe(u8, damaged_line);
        defer allocator.free(mod_line);

        print("\n", .{});
        try expect(expected == try findArrangements(&mod_line, &correct_list));
    }

    {
        const damaged_line = ".??..??...?##.";
        const correct_list = [_]u32{ 1, 1, 3 };
        const expected = 4;

        var mod_line = try allocator.dupe(u8, damaged_line);
        defer allocator.free(mod_line);

        print("\n", .{});
        try expect(expected == try findArrangements(&mod_line, &correct_list));
    }
}

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

    var total_arrangements: usize = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        //print("{s}\n", .{line});

        var split_line = std.mem.splitScalar(u8, line, ' ');

        var correct_list: []u32 = undefined;
        defer allocator.free(correct_list); // This may have a problem if alloc is never called?

        _ = split_line.next();
        if (split_line.next()) |correct_line| {
            // Count number of commas (plus one) to get number of items
            const len = std.mem.count(u8, correct_line, ",") + 1;

            correct_list = try allocator.alloc(u32, len);

            var line_iter = std.mem.splitScalar(u8, correct_line, ',');
            var c_list_i: usize = 0;
            while (line_iter.next()) |c| {
                correct_list[c_list_i] = try std.fmt.parseInt(u32, c, 10);
                c_list_i += 1;
            }
        } // else error.MissingCorrectListEntry;

        split_line.reset();
        if (split_line.next()) |damaged_line| {

            // Copy line so it can be modified in-place
            var mod_line = try allocator.dupe(u8, damaged_line);
            defer allocator.free(mod_line);

            const arr_num = try findArrangements(&mod_line, correct_list);
            total_arrangements += arr_num;

            print("{s} => {}\n", .{ damaged_line, arr_num });
        } // else error.MissingDamageListEntry;
    }

    print("Total Arrangements: {}\n", .{total_arrangements});
}
