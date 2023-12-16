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

    //
    // Mark beam path
    //
    var beam_path = try BeamPath.init(allocator, line_width, line_nums);
    defer beam_path.deinit();
    var seen_path = SeenPath.init(allocator);
    defer seen_path.deinit();

    const test_vectors = [_]TestVector{
        TestVector.init(.{ .x = 0, .y = 0, .dir = .down }, 1, 0, line_width, line_nums),
        TestVector.init(.{ .x = 0, .y = 0, .dir = .right }, 0, 1, line_width, line_nums),
        TestVector.init(.{ .x = line_width - 1, .y = 0, .dir = .left }, 0, 1, line_width, line_nums),
        TestVector.init(.{ .x = 0, .y = line_nums - 1, .dir = .up }, 1, 0, line_width, line_nums),
    };

    var max_energized_tiles: usize = 0;
    var best_start_pos: BeamPosition = .{ .x = 0, .y = 0, .dir = .right };
    var max_steps: usize = 0;
    var max_seen_len: usize = 0;

    for (test_vectors) |tv| {
        var start_pos = BeamPosition{ .x = tv.start_pos.x, .y = tv.start_pos.y, .dir = tv.start_pos.dir };

        while (start_pos.x < tv.inc_x_limit and start_pos.y < tv.inc_y_limit) {
            try markBeamPath(allocator, &map, &beam_path, &seen_path, start_pos, 0);

            const energized_tiles = beam_path.energized_tiles;
            if (energized_tiles > max_energized_tiles) {
                max_energized_tiles = energized_tiles;
                best_start_pos.x = start_pos.x;
                best_start_pos.y = start_pos.y;
                best_start_pos.dir = start_pos.dir;
                max_steps = beam_path.steps;
                max_seen_len = seen_path.count();
            }

            beam_path.clear_path();
            seen_path.clearRetainingCapacity();

            start_pos.x += tv.inc_x;
            start_pos.y += tv.inc_y;
        }
    }

    // Run the best path again so we can print the map
    try markBeamPath(allocator, &map, &beam_path, &seen_path, best_start_pos, 0);

    beam_path.print_path_map();

    print("\nBest Start: {} {} {s} {} {}\n", .{ best_start_pos.x, best_start_pos.y, @tagName(best_start_pos.dir), max_steps, max_seen_len });
    print("Total engergized tiles: {}\n", .{max_energized_tiles});
}

const MapCoord = struct { x: usize, y: usize };

const MapObject = enum { empty, left_mirror, right_mirror, vertical_splitter, horizontal_splitter };

const Map = std.AutoHashMap(MapCoord, MapObject);

const SeenPath = std.AutoHashMap(BeamPosition, void);

const TestVector = struct {
    start_pos: BeamPosition,
    inc_x: usize,
    inc_y: usize,
    inc_x_limit: usize,
    inc_y_limit: usize,

    pub fn init(start_pos: BeamPosition, inc_x: usize, inc_y: usize, inc_x_limit: usize, inc_y_limit: usize) TestVector {
        return .{
            .start_pos = start_pos,
            .inc_x = inc_x,
            .inc_y = inc_y,
            .inc_x_limit = inc_x_limit,
            .inc_y_limit = inc_y_limit,
        };
    }
};

const BeamPosition = struct {
    x: usize,
    y: usize,
    dir: enum { up, down, left, right },
};

const BeamPath = struct {
    path: [][]bool,
    energized_tiles: usize,
    allocator: std.mem.Allocator,
    steps: usize,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !BeamPath {
        var bp: BeamPath = .{ .path = undefined, .energized_tiles = 0, .allocator = allocator, .steps = 0 };
        bp.path = try allocator.alloc([]bool, height);
        for (0..bp.path.len) |i| {
            bp.path[i] = try allocator.alloc(bool, width);
        }
        return bp;
    }

    pub fn deinit(self: BeamPath) void {
        for (self.path) |p| self.allocator.free(p);
        self.allocator.free(self.path);
    }

    pub fn clear_path(self: *BeamPath) void {
        self.steps = 0;
        self.energized_tiles = 0;
        for (0..self.path.len) |y| {
            for (0..self.path[y].len) |x| {
                self.path[y][x] = false;
            }
        }
    }

    pub fn count_energized_tiles(self: BeamPath) usize {
        var energized_tiles: usize = 0;
        for (0..self.path.len) |y| {
            for (0..self.path[y].len) |x| {
                if (self.path[y][x]) energized_tiles += 1;
            }
        }
        return energized_tiles;
    }

    pub fn print_path_map(self: BeamPath) void {
        print("\n", .{});
        for (0..self.path.len) |y| {
            for (0..self.path[y].len) |x| {
                if (self.path[y][x]) {
                    print("#", .{});
                } else {
                    print(".", .{});
                }
            }
            print("\n", .{});
        }
    }
};

pub fn markBeamPath(allocator: std.mem.Allocator, map: *Map, bp: *BeamPath, seen_path: *SeenPath, start: BeamPosition, depth: usize) !void {
    var beam_pos: MapCoord = .{ .x = start.x, .y = start.y };
    var beam_dir = start.dir;

    while (true) {
        // Mark path
        bp.*.steps += 1;
        if (bp.*.path[beam_pos.y][beam_pos.x] == false) {
            bp.*.path[beam_pos.y][beam_pos.x] = true;
            bp.*.energized_tiles += 1;
            //print("{}: Marked {},{}\n", .{ depth, beam_pos.x, beam_pos.y });
        }

        // Detect path loops (captures full path)
        // const loop_detect = try seen_path.getOrPut(.{ .x = beam_pos.x, .y = beam_pos.y, .dir = beam_dir });
        // if (loop_detect.found_existing) return;

        // Check for object
        if (map.get(beam_pos)) |obj| {
            //print("{}: Found  {} {} {s}\n", .{ depth, beam_pos.x, beam_pos.y, @tagName(obj) });

            // Detect path loops (only check inflection points)
            // Note: This reduces the memory used but misses some stopping points so takes more steps to finish.
            // TODO: Probably need to store the opposite direction as well but can't be bothered to do that right now.
            const loop_detect = try seen_path.getOrPut(.{ .x = beam_pos.x, .y = beam_pos.y, .dir = beam_dir });
            if (loop_detect.found_existing) return;

            // Detect direction changes
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
                                    bp,
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
                                    bp,
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
                if (beam_pos.y < bp.path.len - 1) beam_pos.y += 1 else return;
            },
            .left => {
                if (beam_pos.x > 0) beam_pos.x -= 1 else return;
            },
            .right => {
                if (beam_pos.x < bp.path[0].len - 1) beam_pos.x += 1 else return;
            },
        }
    }
}
