const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

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

    var map = Map.init(allocator);
    defer map.deinit();

    var line_nums: usize = 0;
    var line_width: usize = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        for (line, 0..) |c, i| {
            try expect(i < 256 and line_nums < 256);

            const obj: MapObject = switch (c) {
                '.' => .empty,
                '/' => .right_mirror,
                '\\' => .left_mirror,
                '|' => .vertical_splitter,
                '-' => .horizontal_splitter,
                else => return error.BadSymbolInput,
            };

            if (obj != .empty) {
                try map.put(.{ .x = i, .y = line_nums }, obj);
            }
        }
        line_width = @max(line_width, line.len);
        line_nums += 1;
    }

    // Make 2d array for beam path data
    var beam_path = try allocator.alloc([]bool, line_nums);
    for (0..beam_path.len) |i| {
        beam_path[i] = try allocator.alloc(bool, line_width);
    }
    defer {
        for (beam_path) |bp| allocator.free(bp);
        allocator.free(beam_path);
    }

    // Mark beam path
    const start_pos: BeamPosition = .{ .x = 0, .y = 0, .dir = .right };
    var seen_path = SeenPath.init(allocator);
    defer seen_path.deinit();

    try markBeamPath(allocator, &map, &beam_path, &seen_path, start_pos, 0);

    // Count energized tiles and print path map
    var energized_tiles: usize = 0;
    print("\n", .{});
    for (0..beam_path.len) |y| {
        for (0..beam_path[y].len) |x| {
            if (beam_path[y][x]) {
                print("#", .{});
                energized_tiles += 1;
            } else {
                print(".", .{});
            }
        }
        print("\n", .{});
    }

    print("\nTotal engergized tiles: {}\n", .{energized_tiles});
}

const MapCoord = struct { x: usize, y: usize };

const MapObject = enum { empty, left_mirror, right_mirror, vertical_splitter, horizontal_splitter };

const Map = std.AutoHashMap(MapCoord, MapObject);

const SeenPath = std.AutoHashMap(BeamPosition, void);

const BeamPosition = struct {
    x: usize,
    y: usize,
    dir: enum { up, down, left, right },
};

pub fn markBeamPath(allocator: std.mem.Allocator, map: *Map, path: *[][]bool, seen_path: *SeenPath, start: BeamPosition, depth: usize) !void {
    var beam_pos: MapCoord = .{ .x = start.x, .y = start.y };
    var beam_dir = start.dir;

    while (true) {
        // Mark path
        path.*[beam_pos.y][beam_pos.x] = true;
        print("{}: Marked {},{}\n", .{ depth, beam_pos.x, beam_pos.y });

        // Detect path loops
        const loop_detect = try seen_path.getOrPut(.{ .x = beam_pos.x, .y = beam_pos.y, .dir = beam_dir });
        if (loop_detect.found_existing) return;

        // Check for object
        if (map.get(beam_pos)) |obj| {
            print("{}: Found  {} {} {s}\n", .{ depth, beam_pos.x, beam_pos.y, @tagName(obj) });

            switch (obj) {
                .empty => {},
                .left_mirror => beam_dir = switch (beam_dir) {
                    .up => .left,
                    .down => .right,
                    .left => .up,
                    .right => .down,
                },
                .right_mirror => beam_dir = switch (beam_dir) {
                    .up => .right,
                    .down => .left,
                    .left => .down,
                    .right => .up,
                },
                .horizontal_splitter => {
                    switch (beam_dir) {
                        .right, .left => {},
                        .up, .down => {
                            // Split beam.  Right beam continues here, recursive call for left beam.
                            beam_dir = .right;
                            if (beam_pos.x > 0)
                                try markBeamPath(
                                    allocator,
                                    map,
                                    path,
                                    seen_path,
                                    .{ .x = beam_pos.x - 1, .y = beam_pos.y, .dir = .left },
                                    depth + 1,
                                );
                        },
                    }
                },
                .vertical_splitter => {
                    switch (beam_dir) {
                        .up, .down => {},
                        .right, .left => {
                            // Split beam.  Down beam continues here, recursive call for up beam.
                            beam_dir = .down;
                            if (beam_pos.y > 0)
                                try markBeamPath(
                                    allocator,
                                    map,
                                    path,
                                    seen_path,
                                    .{ .x = beam_pos.x, .y = beam_pos.y - 1, .dir = .up },
                                    depth + 1,
                                );
                        },
                    }
                },
            }
        }

        // Move to next position or stop if off map
        switch (beam_dir) {
            .up => {
                if (beam_pos.y > 0) beam_pos.y -= 1 else return;
            },
            .down => {
                if (beam_pos.y < path.len - 1) beam_pos.y += 1 else return;
            },
            .left => {
                if (beam_pos.x > 0) beam_pos.x -= 1 else return;
            },
            .right => {
                if (beam_pos.x < path.*[0].len - 1) beam_pos.x += 1 else return;
            },
        }
    }
}
