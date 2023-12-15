const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

const PlatformCoord = struct {
    x: usize,
    y: usize,
};

const PlatformObject = enum { Rock, HardPlace, Empty };

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

    var platform = std.AutoHashMap(PlatformCoord, PlatformObject).init(allocator);
    defer platform.deinit();

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
                try platform.put(.{ .x = i, .y = line_num }, obj);
            }
        }
        line_num += 1;
        line_width = @max(line_width, line.len);
    }

    // Slide Rocks North
    for (0..line_width) |x| {
        var tail: usize = 0; // North side

        for (0..line_num) |head| {
            const key = PlatformCoord{ .x = x, .y = head };

            if (platform.get(key)) |next_spot| {
                switch (next_spot) {
                    .Empty => {}, // Do nothing (tail should stay here)
                    .HardPlace => {
                        tail = head + 1; // Move tail to next spot after hardplace
                    },
                    .Rock => {
                        if (tail != head) {
                            var tail_key = .{ .x = x, .y = tail };

                            // Move Rock from head to tail
                            try expect(!platform.contains(tail_key));
                            _ = platform.remove(key);
                            try platform.put(tail_key, .Rock);

                            // Move tail to next empty spot (there should be no hardplaces between head and tail)
                            for (tail + 1..head + 1) |i| {
                                if (!platform.contains(.{ .x = x, .y = i })) {
                                    tail = i; // Empty found
                                    break;
                                }
                            } else {
                                tail = head + 1; // No empty spots so move tail to next head position
                            }
                        } else {
                            tail = head + 1; // Advance tail with head
                        }
                    },
                }
            }
        }
    }

    // Calculate Load
    var total_load: usize = 0;

    for (0..line_num) |y| {
        for (0..line_width) |x| {
            const key = PlatformCoord{ .x = x, .y = y };
            if (platform.get(key)) |obj| {
                if (obj == .Rock) {
                    total_load += line_num - y;
                }
            }
        }
    }

    // Print map
    print("\n----\n", .{});
    for (0..line_num) |y| {
        for (0..line_width) |x| {
            const key = PlatformCoord{ .x = x, .y = y };
            switch (platform.get(key) orelse .Empty) {
                .Rock => print("O", .{}),
                .HardPlace => print("#", .{}),
                .Empty => print(".", .{}),
            }
        }
        print("\n", .{});
    }

    print("Total Load: {}\n", .{total_load});
}
