const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

const FinderState = struct {
    index: usize,
    state: State,
    marker_count: usize,
    marker_group: usize,
    depth: usize = 0,

    const State = enum { on_marker, on_gap };
};

pub fn findArrangements(fs: FinderState, damaged_list: *[]u8, correct_list: []const u32, remaining_list: []const u32) !usize {
    var index = fs.index;
    var state = fs.state;
    var marker_count = fs.marker_count;
    var marker_group = fs.marker_group;

    // Verify line one symbol at a time, if an unknown is found recursively test both options
    for (index..damaged_list.*.len) |i| {
        switch (damaged_list.*[i]) {
            '?' => {
                const test_list = [_]u8{ '.', '#' };
                var anum: usize = 0;
                for (test_list) |marker| {
                    if (state == .on_marker and marker == '.' and marker_group < correct_list.len and marker_count + 1 < correct_list[marker_group]) {
                        //print("Skip {c}\n", .{marker});
                        continue;
                    } // No point in adding . if marker is too short
                    damaged_list.*[i] = marker;
                    //print("{}: {s}\n", .{ fs.depth, damaged_list.* });
                    const this_state = .{ .index = i, .state = state, .marker_count = marker_count, .marker_group = marker_group, .depth = fs.depth + 1 };
                    anum += try findArrangements(this_state, damaged_list, correct_list, remaining_list);
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
                    if (marker_group < remaining_list.len and damaged_list.*.len - i < remaining_list[marker_group]) {
                        //print("{}: {s} Remaining {} < {}\n", .{ fs.depth, damaged_list.*, damaged_list.*.len - i, remaining_list[marker_group] });
                        return 0;
                    }
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

pub fn main() !void {
    const repeats: usize = 5;

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
    var line_num: usize = 0;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        //print("{s}\n", .{line});
        var split_line = std.mem.splitScalar(u8, line, ' ');

        // Parse the correct list
        var correct_list: []u32 = undefined;
        defer allocator.free(correct_list); // This may have a problem if alloc is never called?

        _ = split_line.next();
        if (split_line.next()) |correct_line| {
            // Count number of commas (plus one) to get number of items
            const len = (std.mem.count(u8, correct_line, ",") + 1);

            correct_list = try allocator.alloc(u32, len * repeats);

            var line_iter = std.mem.splitScalar(u8, correct_line, ',');
            var c_list_i: usize = 0;
            while (line_iter.next()) |c| {
                for (0..repeats) |i| {
                    correct_list[c_list_i + i * len] = try std.fmt.parseInt(u32, c, 10);
                }
                c_list_i += 1;
            }
        }

        // Create a required remaining list
        var remaining_list = try allocator.dupe(u32, correct_list);
        defer allocator.free(remaining_list);

        if (remaining_list.len > 0) {
            var i = remaining_list.len - 1;
            while (i > 0) {
                i -= 1;
                remaining_list[i] = remaining_list[i] + remaining_list[i + 1] + 1;
            }
        }

        // Parse the damaged list and find number of arrangements
        split_line.reset();
        if (split_line.next()) |damaged_line| {
            var mult_line = try allocator.alloc(u8, (damaged_line.len + 1) * repeats - 1);
            defer allocator.free(mult_line);

            for (0..repeats) |i| {
                std.mem.copyForwards(u8, mult_line[i * (damaged_line.len + 1) ..], damaged_line);
                if (i < repeats - 1) mult_line[i * (damaged_line.len + 1) + damaged_line.len] = '?';
            }

            const fs: FinderState = .{ .index = 0, .state = .on_gap, .marker_count = 0, .marker_group = 0 };

            const ts_start = std.time.microTimestamp();

            const arr_num = try findArrangements(fs, &mult_line, correct_list, remaining_list);

            const ts_end = std.time.microTimestamp();

            total_arrangements += arr_num;

            print("{}: {s} ", .{ line_num, mult_line });
            for (correct_list) |i| {
                print("{}, ", .{i});
            }
            print(" => {}  Comp Time: {d:0.6}s\n", .{ arr_num, (@as(f64, @floatFromInt(ts_end)) - @as(f64, @floatFromInt(ts_start))) / 1000000.0 });
        }
        line_num += 1;
    }

    print("Total Arrangements: {}\n", .{total_arrangements});
}

test "one extra ?" {
    const allocator = std.testing.allocator;

    const damaged_line = "??????#??#???";
    const correct_list = [_]u32{ 1, 1, 5, 1 };
    const expected = 12;

    var mod_line = try allocator.dupe(u8, damaged_line);
    defer allocator.free(mod_line);

    // Create a required remaining list
    var remaining_list = try allocator.dupe(u32, correct_list);
    defer allocator.free(remaining_list);

    if (remaining_list.len > 0) {
        var i = remaining_list.len - 1;
        while (i > 0) {
            i -= 1;
            remaining_list[i] = remaining_list[i] + remaining_list[i + 1] + 1;
        }
    }

    print("\nTesting: {s}\n", .{damaged_line});

    const fs: FinderState = .{ .index = 0, .state = .on_gap, .marker_count = 0, .marker_group = 0 };

    const ts_start = std.time.microTimestamp();

    const result = try findArrangements(fs, &mod_line, &correct_list, remaining_list);

    const ts_end = std.time.microTimestamp();

    print("Result: {}  Comp Time: {e:0.3}s\n", .{ result, (@as(f64, ts_end) - @as(f64, ts_start)) / 1000000.0 });
    try expect(result == expected);
}

// test "5 dupplicates" {
//     const allocator = std.testing.allocator;

//     const damaged_line = "??????#??#?????????#??#?????????#??#?????????#??#?????????#??#??";
//     const correct_list = [_]u32{ 1, 1, 5, 1 } ** 5;
//     const expected = 6444;

//     var mod_line = try allocator.dupe(u8, damaged_line);
//     defer allocator.free(mod_line);

//     print("\nTesting: {s}\n", .{damaged_line});

//     const fs: FinderState = .{ .index = 0, .state = .on_gap, .marker_count = 0, .marker_group = 0 };

//     const result = try findArrangements(fs, &mod_line, &correct_list);

//     print("Result: {}\n", .{result});
//     try expect(result == expected);
// }

// test "long comp time" {
//     const allocator = std.testing.allocator;

//     const damaged_line = "????????.?#???#??##??????????.?#???#??##??????????.?#???#??##??????????.?#???#??##??????????.?#???#??##?";
//     const correct_list = [_]u32{ 2, 1, 2, 1, 1, 6 } ** 5;
//     const expected = 1024;

//     var mod_line = try allocator.dupe(u8, damaged_line);
//     defer allocator.free(mod_line);

//     print("\nTesting: {s}\n", .{damaged_line});

//     const fs: FinderState = .{ .index = 0, .state = .on_gap, .marker_count = 0, .marker_group = 0 };

//     const result = try findArrangements(fs, &mod_line, &correct_list);

//     print("Result: {}\n", .{result});
//     try expect(result == expected);
// }
