const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

const PlatformCoord = struct {
    x: usize,
    y: usize,
};

const PlatformObject = enum { Rock, HardPlace, Empty };

const PlatformMap = std.AutoHashMap(PlatformCoord, PlatformObject);

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

    // Hard code size of buffer for now because AutoHashMap wouldn't work
    var platform_list: [200]PlatformMap = undefined;
    var platform_list_head: usize = 0;
    defer {
        for (0..platform_list_head) |i| {
            platform_list[i].deinit();
        }
    }

    // Allocate space for initial map
    platform_list[0] = PlatformMap.init(allocator);
    platform_list_head += 1;

    var line_num: usize = 0;
    var line_width: usize = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        print("{s}\n", .{line});

        for (line, 0..) |c, i| {
            const obj: PlatformObject = switch (c) {
                'O' => .Rock,
                '#' => .HardPlace,
                '.' => .Empty,
                else => return error.BadSymbol,
            };
            if (obj != .Empty) {
                try platform_list[0].put(.{ .x = i, .y = line_num }, obj);
            }
        }
        line_num += 1;
        line_width = @max(line_width, line.len);
    }

    // Shake the platform
    var cycle_result_map = std.AutoHashMap(u64, u64).init(allocator);
    defer cycle_result_map.deinit();

    var stored_platforms = std.AutoHashMap(u64, usize).init(allocator);
    defer stored_platforms.deinit();

    const run_cycles: usize = 1000000000;
    print("\nRunning {} cycles...\n", .{run_cycles});

    const cycle_sequence = [_]Direction{ .north, .west, .south, .east };

    var current_platform_hash = try platform_hash(allocator, &platform_list[0], line_width, line_num);
    try stored_platforms.put(current_platform_hash, 0);

    for (0..run_cycles) |cycle| {
        if (@mod(cycle, 100000000) == 0) {
            print("On cycle {}\n", .{cycle});
        }

        if (cycle_result_map.get(current_platform_hash)) |result_hash| {
            current_platform_hash = result_hash;

            // if (stored_platforms.get(current_platform_hash)) |index| {
            //     try expect(index < platform_list_head);
            //     print("Hash {x:0>8} found {}\n", .{ current_platform_hash, index });
            // }
        } else {
            var platform_index: usize = undefined;

            if (stored_platforms.get(current_platform_hash)) |index| {
                platform_index = index;
                try expect(platform_index < platform_list_head);

                // Create new copy to modify
                platform_list[platform_list_head] = try platform_list[platform_index].clone();
                platform_index = platform_list_head;
                platform_list_head += 1;
            } else {
                return error.PlatformNotFound;
            }

            // Slide the platform to get result
            //print("{}: Sliding Rocks idx = {} ptr = {*}\n", .{ cycle, platform_index, &platform_list[platform_index] });
            for (cycle_sequence) |dir| {
                //print("{}: Sliding Rocks {s}\n", .{cycle, @tagName(dir)});
                try slideRocks(&platform_list[platform_index], line_width, line_num, dir);
                //print_platform(&platform, line_width, line_num);
            }

            const computed_hash = try platform_hash(allocator, &platform_list[platform_index], line_width, line_num);
            try cycle_result_map.put(current_platform_hash, computed_hash);
            try stored_platforms.put(computed_hash, platform_index);

            current_platform_hash = computed_hash;

            // print("\n---- After Cycle {} ----\n", .{cycle});
            // print_platform(&platform_list[platform_index], line_width, line_num);
        }

        // print("\n---- After Cycle {} ----\n", .{cycle});
        // print_platform(&platform_list[platform_index], line_width, line_num);
    }

    // Update the platform with the last hash value
    var result_index: usize = undefined;
    if (stored_platforms.get(current_platform_hash)) |index| {
        result_index = index;
    } else {
        return error.PlatformNotFound;
    }

    // Calculate Load
    var total_load: usize = 0;
    for (0..line_num) |y| {
        for (0..line_width) |x| {
            const key = PlatformCoord{ .x = x, .y = y };
            if (platform_list[result_index].get(key)) |obj| {
                if (obj == .Rock) {
                    total_load += line_num - y;
                }
            }
        }
    }

    // Print map
    print("\n", .{});
    print_platform(&platform_list[result_index], line_width, line_num);
    print("\nTotal Load: {}\n", .{total_load});
}

const Direction = enum {
    north,
    east,
    south,
    west,

    pub fn loop_test(dir: Direction, head_or_tail: usize, width_or_height: usize) bool {
        return switch (dir) {
            .north, .west => head_or_tail < width_or_height, // Moving toward width or height
            .south, .east => head_or_tail > 0, // Moving toward 0
        };
    }

    pub fn tail_advance(dir: Direction, head: usize) usize {
        return switch (dir) {
            .north, .west => head + 1,
            .south, .east => if (head > 0) head - 1 else 0,
        };
    }

    pub fn head_or_tail_start(dir: Direction, width: usize, height: usize) usize {
        return switch (dir) {
            .north, .west => 0,
            .south => height,
            .east => width,
        };
    }

    const HeadOrTail = enum { head, tail };

    pub fn head_or_tail_range(dir: Direction, head: usize, tail: usize, flip: HeadOrTail) usize {
        return switch (dir) {
            .north, .west => if (flip == .head) head + 1 else tail + 1,
            .south, .east => if (flip == .head) if (tail > 0) tail - 1 else 0 else if (head > 0) head - 1 else 0,
        };
    }

    pub fn get_coord(dir: Direction, x: usize, y: usize) PlatformCoord {
        const sx = switch (dir) {
            .north, .south => x,
            .west, .east => y,
        };
        const sy = switch (dir) {
            .north, .south => y,
            .west, .east => x,
        };
        return PlatformCoord{ .x = sx, .y = sy };
    }
};

pub fn slideRocks(platform: *PlatformMap, width: usize, height: usize, direction: Direction) !void {
    const end_row = switch (direction) {
        .north, .south => width,
        .west, .east => height,
    };

    for (0..end_row) |row| {
        var tail: usize = direction.head_or_tail_start(width, height);
        var head: usize = direction.head_or_tail_start(width, height);

        switch (direction) {
            .south, .east => tail -= 1, // Fix starting tail position so it matches head during first loop
            else => {},
        }

        while (direction.loop_test(head, height)) {
            switch (direction) {
                .south, .east => head -= 1,
                else => {},
            }
            const key = direction.get_coord(row, head); //PlatformCoord{ .x = x, .y = head };

            if (platform.get(key)) |next_spot| {
                switch (next_spot) {
                    .Empty => {}, // Do nothing (tail should stay here)
                    .HardPlace => {
                        tail = direction.tail_advance(head); // Move tail to next spot after hardplace
                    },
                    .Rock => {
                        if (tail != head) {
                            var tail_key = direction.get_coord(row, tail); //.{ .x = x, .y = tail };

                            // Move Rock from head to tail
                            try expect(!platform.contains(tail_key));
                            _ = platform.remove(key);
                            try platform.put(tail_key, .Rock);

                            // Move tail to next empty spot (there should be no hardplaces between head and tail)
                            var s = direction.head_or_tail_range(head, tail, .tail);
                            var e = direction.head_or_tail_range(head, tail, .head);
                            for (s..e, 0..) |_, i| { // This look a mess because for loops can not decrement range
                                var next_tail = switch (direction) {
                                    .north, .west => s + i,
                                    .south, .east => e - i,
                                };
                                if (!platform.contains(direction.get_coord(row, next_tail))) {
                                    tail = next_tail; // Empty found
                                    break;
                                }
                            } else {
                                tail = direction.tail_advance(head); // No empty spots so move tail to next head position
                            }
                        } else {
                            tail = direction.tail_advance(head); // Advance tail with head
                        }
                    },
                }
            }

            switch (direction) {
                .north, .west => head += 1,
                else => {},
            }
        }
    }
}

pub fn print_platform(platform: *const PlatformMap, width: usize, height: usize) void {
    for (0..height) |y| {
        for (0..width) |x| {
            const key = PlatformCoord{ .x = x, .y = y };
            switch (platform.get(key) orelse .Empty) {
                .Rock => print("O", .{}),
                .HardPlace => print("#", .{}),
                .Empty => print(".", .{}),
            }
        }
        print("\n", .{});
    }
}

pub fn platform_hash(allocator: std.mem.Allocator, platform: *const PlatformMap, width: usize, height: usize) !u64 {
    var buf_array = std.ArrayList(u8).init(allocator);
    defer buf_array.deinit();
    const buf = buf_array.writer();

    for (0..height) |y| {
        for (0..width) |x| {
            const key = PlatformCoord{ .x = x, .y = y };
            switch (platform.get(key) orelse .Empty) {
                .Rock => try buf.writeByte('O'),
                .HardPlace => try buf.writeByte('#'),
                .Empty => try buf.writeByte('.'),
            }
        }
    }
    return std.hash_map.hashString(buf_array.items);
}

test "hash" {
    const str = "O....#....O.OO#....#.....##...OO.#O....O.O.....O#.O.#..O.#.#..O..#O..O.......O..#....###..#OO..#....";

    print("\n{x}\n", .{std.hash_map.hashString(str)});
}

test "clone hashmap" {
    const allocator = std.testing.allocator;

    var platform = PlatformMap.init(allocator);
    defer platform.deinit();

    try platform.put(.{ .x = 2, .y = 8 }, .Rock);

    var platform_copy = try platform.clone();
    defer platform_copy.deinit();
}
