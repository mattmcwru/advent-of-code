const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

const SpringState = enum { operational, damaged, unknown };
const DamagedList = std.ArrayList(SpringState);
const CorrectList = std.ArrayList(u8);

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

    var damaged_list = DamagedList.init(allocator);
    defer damaged_list.deinit();
    var correct_list = CorrectList.init(allocator);
    defer correct_list.deinit();

    var total_arrangements: usize = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var split_line = std.mem.splitScalar(u8, line, ' ');

        // Get damaged list
        if (split_line.next()) |sl| {
            print("{s}", .{sl});
            defer print("\n", .{});

            for (sl) |c| {
                try damaged_list.append(switch (c) {
                    '.' => .operational,
                    '#' => .damaged,
                    '?' => .unknown,
                    else => return error.BadSymbolInput,
                });
            }
        } else return error.MissingDamageList;

        // Get correct list
        if (split_line.next()) |sl| {
            var split_num = std.mem.splitScalar(u8, sl, ',');
            while (split_num.next()) |n| {
                try correct_list.append(try std.fmt.parseInt(u8, n, 10));
            }
        }

        // Find number of arrangements
        var state = FinderState{
            .state = .on_gap,
            .index = 0,
            .marker_group = 0,
            .marker_count = 0,
            .depth = 0,
        };
        const arrangements = try findArrangements(&state, &damaged_list, &correct_list);
        total_arrangements += arrangements;

        print("Arrangements: {}\n", .{arrangements});

        // Clear for next iteration
        correct_list.clearRetainingCapacity();
        damaged_list.clearRetainingCapacity();
    }

    print("Total Arrangements: {}\n", .{total_arrangements});
}

const FinderState = struct {
    state: State,
    index: usize,
    marker_group: usize,
    marker_count: usize,
    depth: usize = 0,

    const State = enum { on_marker, on_gap };
};

pub fn findArrangements(fs: *FinderState, damaged_list: *DamagedList, correct_list: *CorrectList) !usize {
    var index = fs.index;
    var state = fs.state;
    var marker_count = fs.marker_count;
    var marker_group = fs.marker_group;

    // Verify line one symbol at a time, if an unknown is found recursively test both options
    for (index..damaged_list.items.len) |i| {
        switch (damaged_list.items[i]) {
            .unknown => {
                const test_list = [_]SpringState{ .operational, .damaged };
                var anum: usize = 0;
                var skip_operational: bool = false;
                var skip_damaged: bool = false;

                // If on marker group then check spaces remaining spaces required for current group
                if (state == .on_marker) {
                    const needed_markers = correct_list.items[marker_group] - marker_count;
                    if (i + needed_markers > damaged_list.items.len) {
                        //print(" Kick: {} {} {}\n", .{ needed_markers, marker_count, correct_list.items[marker_group] });
                        return 0; // Out of space for markers
                    }
                    if (needed_markers == 0) {
                        skip_damaged = true;
                    } else {
                        skip_operational = true;
                        for (1..needed_markers) |k| {
                            switch (damaged_list.items[i + k]) {
                                .damaged, .unknown => {},
                                .operational => return 0, // Can not complete group
                            }
                        }
                    }
                }

                for (test_list) |marker| {
                    if (marker == .operational and skip_operational) continue;
                    if (marker == .damaged and skip_damaged) continue;

                    var this_state = FinderState{
                        .index = i,
                        .state = state, //switch(marker) { .operational => .on_gap, .damaged => .on_marker },
                        .marker_count = marker_count,
                        .marker_group = marker_group,
                        .depth = fs.depth + 1,
                    };

                    damaged_list.items[i] = marker;

                    print(">{}: ", .{fs.depth});
                    print_damage_list(damaged_list);

                    anum += try findArrangements(&this_state, damaged_list, correct_list);

                    print("<{}: {}\n", .{ fs.depth, anum });
                }
                damaged_list.items[i] = .unknown;
                return anum;
            },
            .damaged => {
                marker_count = if (state == .on_gap) 1 else marker_count + 1;
                if (marker_group >= correct_list.items.len or marker_count > correct_list.items[marker_group]) return 0; // Markers in group too many

                if (state == .on_gap) {
                    // Check if enough spaces for markers in current group
                    const needed_markers = correct_list.items[marker_group] - marker_count;
                    if (i + needed_markers >= damaged_list.items.len) return 0; // Out of space for markers
                    for (0..needed_markers) |k| {
                        switch (damaged_list.items[i + k]) {
                            .damaged, .unknown => {},
                            .operational => return 0, // Can not complete group
                        }
                    }
                }
                state = .on_marker;
            },
            .operational => {
                if (state == .on_marker) {
                    if (marker_group >= correct_list.items.len or marker_count != correct_list.items[marker_group]) return 0; // Marker number differs
                    marker_group += 1;
                    marker_count = 0;
                    // if (marker_group < remaining_list.len and damaged_list.*.len - i < remaining_list[marker_group]) {
                    //     //print("{}: {s} Remaining {} < {}\n", .{ fs.depth, damaged_list.*, damaged_list.*.len - i, remaining_list[marker_group] });
                    //     return 0;
                    // }
                }
                state = .on_gap;
            },
        }
    } else {
        // No unknown markers found
        if (state == .on_marker) {
            if (marker_group >= correct_list.items.len or marker_count != correct_list.items[marker_group]) return 0; // Marker number differs
            marker_group += 1;
        }
        if (marker_group != correct_list.items.len) return 0; // Number of marker groups and corrects differ

        return 1; // Good arrangement found
    }

    return 0;
}

test "findArrangements no unknowns" {
    const allocator = std.testing.allocator;

    const test_damaged = [_][]const u8{ "???.###", "??..##...###.#.####." };
    const test_correct = [_][]const u8{ "1,1,3", "2,3,1,4" };
    const test_expected = [_]usize{ 1, 1 };

    print("\n", .{});

    for (test_damaged, test_correct, test_expected) |d_list, c_list, e_val| {
        var damaged_list = DamagedList.init(allocator);
        defer damaged_list.deinit();
        var correct_list = CorrectList.init(allocator);
        defer correct_list.deinit();

        for (d_list) |c| {
            try damaged_list.append(switch (c) {
                '.' => .operational,
                '#' => .damaged,
                '?' => .unknown,
                else => return error.BadSymbolInput,
            });
        }

        var split_num = std.mem.splitScalar(u8, c_list, ',');
        while (split_num.next()) |n| {
            try correct_list.append(try std.fmt.parseInt(u8, n, 10));
        }

        var state = FinderState{
            .state = .on_gap,
            .index = 0,
            .marker_group = 0,
            .marker_count = 0,
            .depth = 0,
        };

        print("{s} {s} ", .{ d_list, c_list });
        const arrangements = try findArrangements(&state, &damaged_list, &correct_list);
        print("Arrangements found: {}\n", .{arrangements});

        try expect(e_val == arrangements);
    }
}

pub fn print_damage_list(list: *DamagedList) void {
    for (list.items) |item| {
        switch (item) {
            .operational => print(".", .{}),
            .damaged => print("#", .{}),
            .unknown => print("?", .{}),
        }
    }
    print("\n", .{});
}
