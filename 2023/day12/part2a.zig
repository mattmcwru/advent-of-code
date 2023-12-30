const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

const DualFinderState = struct {
    left: FinderState,
    right: FinderState,
    depth: usize = 0,

    pub fn init() DualFinderState {
        return .{
            .left = .{ .index = 0, .state = .on_gap, .marker_count = 0, .marker_group = 0 },
            .right = .{ .index = 0, .state = .on_gap, .marker_count = 0, .marker_group = 0 },
        };
    }
};

const FinderState = struct {
    index: usize,
    state: State,
    marker_count: usize,
    marker_group: usize,
    depth: usize = 0,

    const State = enum { on_marker, on_gap };
};

pub fn findDualArrangements(fs: DualFinderState, damaged_list: *[]u8, correct_list: []const u32, remaining_list: []const u32) !usize {
    var left_index = fs.left.index;
    var left_state = fs.left.state;
    var left_marker_count = fs.left.marker_count;
    var left_marker_group = fs.left.marker_group;

    var right_index = fs.right.index;
    var right_state = fs.right.state;
    var right_marker_count = fs.right.marker_count;
    var right_marker_group = fs.right.marker_group;

    //print("---- {} {}\n", .{ left_index, right_index });

    var left_unknown_found = false;
    var right_unknown_found = false;

    // Check right side until unknown if found
    while (left_index < right_index) : (right_index -= 1) {
        switch (damaged_list.*[right_index]) {
            '?' => {
                //print("Break Right {}\n", .{right_index});
                right_unknown_found = true;
                break;
            },
            '#' => {
                if (right_state == .on_gap) {
                    if (right_marker_group > 0) right_marker_group -= 1 else {
                        //print("  TR1: {s}  {} {}\n", .{ damaged_list.*, left_index, right_index });
                        return 0;
                    }
                }
                right_marker_count = if (right_state == .on_gap) 1 else right_marker_count + 1;
                if (right_marker_count > correct_list[right_marker_group]) {
                    //print("  TR2: {s}  {} {} {} > {}\n", .{ damaged_list.*, left_index, right_index, right_marker_count, correct_list[right_marker_group] });
                    return 0; // Markers in group too many
                }
                right_state = .on_marker;
            },
            '.' => {
                if (right_state == .on_marker) {
                    if (right_marker_count != correct_list[right_marker_group]) {
                        //print("  TR3: {s}  {} {}\n", .{ damaged_list.*, left_index, right_index });
                        return 0; // Marker number differs
                    }
                }
                right_state = .on_gap;
            },
            else => return error.BadSymbolInput,
        }
    } else {
        //print("Right skip\n", .{});
    }

    // Check left side until unknown if found
    const upper_index = if (right_unknown_found) right_index else damaged_list.*.len;
    while (left_index < upper_index) : (left_index += 1) {
        switch (damaged_list.*[left_index]) {
            '?' => {
                //print("Break Left {}\n", .{left_index});
                left_unknown_found = true;
                break;
            },
            '#' => {
                left_marker_count = if (left_state == .on_gap) 1 else left_marker_count + 1;
                if (left_marker_group >= correct_list.len or left_marker_count > correct_list[left_marker_group]) return 0; // Markers in group too many
                left_state = .on_marker;
            },
            '.' => {
                if (left_state == .on_marker) {
                    if (left_marker_group >= correct_list.len or left_marker_count != correct_list[left_marker_group]) return 0; // Marker number differs
                    left_marker_group += 1;
                }
                left_state = .on_gap;
            },
            else => return error.BadSymbolInput,
        }
    } else {
        //print("No Unknown Left {s} {s} {}\n", .{ damaged_list.*, @tagName(left_state), left_marker_group });
        // No unknown markers found
        if (!right_unknown_found) {
            if (left_state == .on_marker) {
                if (left_marker_group >= correct_list.len or left_marker_count != correct_list[left_marker_group]) {
                    //print("  TL4: {s}  {} {} : {} != {}\n", .{ damaged_list.*, left_index, right_index, left_marker_count, correct_list[left_marker_group] });
                    return 0; // Marker number differs
                }
                left_marker_group += 1;
            }
            if (left_marker_group != correct_list.len) {
                //print("  TL5: {s}  {} {} : {} != 0\n", .{ damaged_list.*, left_index, right_index, left_marker_group });
                return 0; // Number of marker groups and corrects differ
            }

            //print("GGL: {s}\n", .{damaged_list.*});
            return 1; // Good arrangement found
        }
    }

    var anum: usize = 0;
    const test_list = [_]u8{ '.', '#' };
    const this_state = .{
        .left = .{
            .index = left_index,
            .state = left_state,
            .marker_count = left_marker_count,
            .marker_group = left_marker_group,
        },
        .right = .{
            .index = right_index,
            .state = right_state,
            .marker_count = right_marker_count,
            .marker_group = right_marker_group,
        },
        .depth = fs.depth + 1,
    };

    try expect(left_unknown_found or right_unknown_found);

    for (test_list) |left_marker| {
        if (left_unknown_found) damaged_list.*[left_index] = left_marker;

        for (test_list) |right_marker| {
            if (right_unknown_found) damaged_list.*[right_index] = right_marker;

            //print("{}: FD {s}  {} {}\n", .{ fs.depth, damaged_list.*, left_index, right_index });
            anum += try findDualArrangements(this_state, damaged_list, correct_list, remaining_list);

            if (!right_unknown_found) break;
        }
        if (right_unknown_found) damaged_list.*[right_index] = '?';

        if (!left_unknown_found) break;
    }
    if (left_unknown_found) damaged_list.*[left_index] = '?';

    return anum;
}

pub fn findArrangements(fs: FinderState, damaged_list: *[]u8, correct_list: []const u32, remaining_list: []const u32) !usize {
    var index = fs.index;
    var state = fs.state;
    var marker_count = fs.marker_count;
    var marker_group = fs.marker_group;

    print("S:  {s}\n", .{damaged_list.*});

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

            var fs = DualFinderState.init();
            fs.right.index = mult_line.len - 1;
            fs.right.marker_group = correct_list.len;

            const ts_start = std.time.microTimestamp();

            const arr_num = try findDualArrangements(fs, &mult_line, correct_list, remaining_list);

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

// test "one extra ?" {
//     const allocator = std.testing.allocator;

//     const damaged_line = "??????#??#???";
//     const correct_list = [_]u32{ 1, 1, 5, 1 };
//     const expected = 12;

//     var mod_line = try allocator.dupe(u8, damaged_line);
//     defer allocator.free(mod_line);

//     // Create a required remaining list
//     var remaining_list = try allocator.dupe(u32, correct_list);
//     defer allocator.free(remaining_list);

//     if (remaining_list.len > 0) {
//         var i = remaining_list.len - 1;
//         while (i > 0) {
//             i -= 1;
//             remaining_list[i] = remaining_list[i] + remaining_list[i + 1] + 1;
//         }
//     }

//     print("\nTesting: {s}\n", .{damaged_line});

//     const fs: DualFinderState.init();

//     const ts_start = std.time.milliTimestamp();

//     const result = try findArrangements(fs, &mod_line, &correct_list, remaining_list);

//     const ts_end = std.time.milliTimestamp();

//     print("Result: {}  Comp Time: {e:0.3}s\n", .{ result, (@as(f64, ts_end) - @as(f64, ts_start)) / 1000.0 });
//     try expect(result == expected);
// }

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
