const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

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

    var spring_list = std.ArrayList(SpringState).init(allocator);
    defer spring_list.deinit();
    var damaged_list = std.ArrayList(u8).init(allocator);
    defer damaged_list.deinit();
    var finder_cache = FinderCache.init(allocator);
    defer {
        var iter = finder_cache.keyIterator();
        while (iter.next()) |key| allocator.free(key.*);
        finder_cache.deinit();
    }

    var total_arrangements: usize = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var split_line = std.mem.splitAny(u8, line, " ,");

        spring_list.clearRetainingCapacity();
        damaged_list.clearRetainingCapacity();

        var iter = finder_cache.keyIterator();
        while (iter.next()) |key| allocator.free(key.*);
        finder_cache.clearRetainingCapacity();

        if (split_line.next()) |springs| {
            for (springs) |spring| {
                try spring_list.append(switch (spring) {
                    '.' => .working,
                    '#' => .damaged,
                    '?' => .unknown,
                    else => return error.BadSymbolInput,
                });
            }
        } else return error.MissingSpringList;

        while (split_line.next()) |damaged| {
            try damaged_list.append(try std.fmt.parseInt(u8, damaged, 10));
        }

        var spring_slice = try spring_list.toOwnedSlice();
        defer allocator.free(spring_slice);
        var damaged_slice = try damaged_list.toOwnedSlice();
        defer allocator.free(damaged_slice);

        print("{any} ", .{damaged_slice});
        print_spring_list(&spring_slice);

        const arrangements = try findArrangements(
            .{
                .state = .on_gap,
                .index = 0,
                .marker_group = 0,
                .marker_count = 0,
                .depth = 0,
                .allocator = allocator,
            },
            &spring_slice,
            &damaged_slice,
            &finder_cache,
        );

        print("Arrangements: {}\n", .{arrangements});

        total_arrangements += arrangements;
    }
    print("\nTotal Arrangements: {}\n", .{total_arrangements});
}

const SpringState = enum { working, damaged, unknown };
const SpringList = []SpringState;
const DamagedList = []u8;

const FinderCache = std.HashMap(SpringList, usize, FinderKeyCtx, std.hash_map.default_max_load_percentage);

const FinderKeyCtx = struct {
    pub fn hash(_: FinderKeyCtx, springs: SpringList) u64 {
        var h = std.hash.Wyhash.init(0xDEADBEEF);
        for (springs) |spring| {
            h.update(switch (spring) {
                .working => ".",
                .damaged => "#",
                .unknown => "?",
            });
        }
        return h.final();
    }

    pub fn eql(_: FinderKeyCtx, a: SpringList, b: SpringList) bool {
        return std.mem.eql(SpringState, a, b);
    }
};

const FinderState = struct {
    state: State,
    index: usize,
    marker_group: usize,
    marker_count: usize,
    depth: usize = 0,
    allocator: std.mem.Allocator,

    const State = enum { on_marker, on_gap };
};

pub fn findArrangements(fs: FinderState, spring_list: *SpringList, damaged_list: *DamagedList, finder_cache: *FinderCache) !usize {
    var index = fs.index;
    var state = fs.state;
    var marker_count = fs.marker_count;
    var marker_group = fs.marker_group;

    // Verify line one symbol at a time, if an unknown is found recursively test both options
    for (index..spring_list.*.len) |i| {
        switch (spring_list.*[i]) {
            .unknown => {
                const test_list = [_]SpringState{ .working, .damaged };
                var anum: usize = 0;
                var skip_working: bool = false;
                var skip_damaged: bool = false;

                // If on marker group then check spaces remaining spaces required for current group
                if (state == .on_marker) {
                    const needed_markers = damaged_list.*[marker_group] - marker_count;
                    if (i + needed_markers > spring_list.*.len) {
                        //print(" Kick: {} {} {}\n", .{ needed_markers, marker_count, damaged_list.items[marker_group] });
                        return 0; // Out of space for markers
                    }
                    if (needed_markers == 0) {
                        skip_damaged = true;
                    } else {
                        skip_working = true;
                        for (1..needed_markers) |k| {
                            switch (spring_list.*[i + k]) {
                                .damaged, .unknown => {},
                                .working => return 0, // Can not complete group
                            }
                        }
                    }
                }

                for (test_list) |marker| {
                    if ((marker == .working and skip_working) or
                        (marker == .damaged and skip_damaged)) continue;

                    //print(">{}: ", .{fs.depth});
                    //print_spring_list(spring_list);

                    spring_list.*[i] = marker;

                    if (finder_cache.get(spring_list.*)) |found_anum| {
                        print("Found \n", .{});
                        anum += found_anum;
                    } else {
                        const found_anum = try findArrangements(
                            .{
                                .index = i,
                                .state = state,
                                .marker_count = marker_count,
                                .marker_group = marker_group,
                                .depth = fs.depth + 1,
                                .allocator = fs.allocator,
                            },
                            spring_list,
                            damaged_list,
                            finder_cache,
                        );

                        try finder_cache.put(try fs.allocator.dupe(SpringState, spring_list.*), found_anum);
                        anum += found_anum;
                    }

                    //print("<{}: {}\n", .{ fs.depth, anum });
                }
                spring_list.*[i] = .unknown;
                return anum;
            },
            .damaged => {
                marker_count = if (state == .on_gap) 1 else marker_count + 1;
                if (marker_group >= damaged_list.*.len or marker_count > damaged_list.*[marker_group]) return 0; // Markers in group too many

                if (state == .on_gap) {
                    // Check if enough spaces for markers in current group
                    const needed_markers = damaged_list.*[marker_group] - marker_count;
                    if (i + needed_markers >= spring_list.*.len) return 0; // Out of space for markers
                    for (0..needed_markers) |k| {
                        switch (spring_list.*[i + k]) {
                            .damaged, .unknown => {},
                            .working => return 0, // Can not complete group
                        }
                    }
                }
                state = .on_marker;
            },
            .working => {
                if (state == .on_marker) {
                    if (marker_group >= damaged_list.*.len or marker_count != damaged_list.*[marker_group]) return 0; // Marker number differs
                    marker_group += 1;
                    marker_count = 0;
                    // if (marker_group < remaining_list.len and spring_list.*.len - i < remaining_list[marker_group]) {
                    //     //print("{}: {s} Remaining {} < {}\n", .{ fs.depth, spring_list.*, spring_list.*.len - i, remaining_list[marker_group] });
                    //     return 0;
                    // }
                }
                state = .on_gap;
            },
        }
    } else {
        // No unknown markers found
        if (state == .on_marker) {
            if (marker_group >= damaged_list.*.len or marker_count != damaged_list.*[marker_group]) return 0; // Marker number differs
            marker_group += 1;
        }
        if (marker_group != damaged_list.*.len) return 0; // Number of marker groups and corrects differ

        return 1; // Good arrangement found
    }

    return 0;
}

pub fn print_spring_list(springs: *SpringList) void {
    for (springs.*) |spring| {
        switch (spring) {
            .working => print(".", .{}),
            .damaged => print("#", .{}),
            .unknown => print("?", .{}),
        }
    }
    print("\n", .{});
}
