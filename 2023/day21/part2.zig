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

    var map_height: usize = 0;
    var map_width: usize = 0;

    var start_point: GardenMap.MapCoord = undefined;

    var map = GardenMap.init(allocator);
    defer map.deinit();

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        for (0..line.len) |x| {
            switch (line[x]) {
                'S' => {
                    start_point = .{ .x = x, .y = map_height };
                    try map.put(x, map_height, .Path);
                },
                '.' => try map.put(x, map_height, .Path),
                '#' => try map.put(x, map_height, .Rock),
                else => return error.BadSymbol,
            }
        }
        map_width = @max(line.len, map_width);
        map_height += 1;
    }

    // Print Map
    //map.printMap();
    try map.printWorldMap(-11, -11, 22, 22);

    // Find number of plots reached by each step
    var plots_reached = std.ArrayList(GardenMap.WorldCoord).init(allocator);
    defer plots_reached.deinit();
    try plots_reached.append(.{
        .x = @as(isize, @intCast(start_point.x)),
        .y = @as(isize, @intCast(start_point.y)),
    });

    var next_plots = std.AutoHashMap(GardenMap.WorldCoord, GardenMap.WorldCoord).init(allocator);
    defer next_plots.deinit();

    const dirs = [_]GardenMap.Direction{ .left, .right, .up, .down };
    const steps: usize = 100;

    for (0..steps) |step| {
        _ = step;
        while (plots_reached.popOrNull()) |plot| {
            for (dirs) |dir| {
                if (try map.isWorldNeighbor(plot, dir, .Path)) |np| try next_plots.put(np, np);
            }
        }

        // Move items from next_plots to plots_reached
        var iter = next_plots.valueIterator();
        while (iter.next()) |plot| {
            try plots_reached.append(plot.*);
        }
        next_plots.clearRetainingCapacity();

        //print("Plots reached after step {}: {}\n", .{ step + 1, plots_reached.items.len });
    }
    print("Plots reached after step {}: {}\n", .{ steps, plots_reached.items.len });
}

const GardenMap = struct {
    map: std.AutoHashMap(MapCoord, GardenObject),
    width: usize,
    height: usize,
    allocator: std.mem.Allocator,

    const MapType = std.AutoHashMap(MapCoord, GardenObject);

    const MapCoord = struct {
        x: usize,
        y: usize,
    };

    const WorldCoord = struct {
        x: isize,
        y: isize,
    };

    const GardenObject = enum { Path, Rock };
    const Direction = enum { left, right, up, down };

    pub fn init(allocator: std.mem.Allocator) GardenMap {
        return .{ .map = MapType.init(allocator), .width = 0, .height = 0, .allocator = allocator };
    }

    pub fn deinit(self: *GardenMap) void {
        self.map.deinit();
    }

    pub fn get(self: GardenMap, x: usize, y: usize) ?GardenObject {
        return self.map.get(.{ .x = x, .y = y });
    }

    pub fn put(self: *GardenMap, x: usize, y: usize, V: GardenObject) !void {
        try self.map.put(.{ .x = x, .y = y }, V);
        self.width = @max(self.width, x + 1);
        self.height = @max(self.height, y + 1);
    }

    pub fn isNeighbor(self: GardenMap, at: MapCoord, dir: Direction, object: GardenObject) ?MapCoord {
        const neighbor_coord: MapCoord = switch (dir) {
            .left => if (at.x > 0) .{ .x = at.x - 1, .y = at.y } else return null,
            .right => if (at.x < self.width - 1) .{ .x = at.x + 1, .y = at.y } else return null,
            .up => if (at.y > 0) .{ .x = at.x, .y = at.y - 1 } else return null,
            .down => if (at.y < self.height) .{ .x = at.x, .y = at.y + 1 } else return null,
        };
        if (self.map.get(neighbor_coord)) |obj|
            if (obj == object) return neighbor_coord;
        return null;
    }

    pub fn isWorldNeighbor(self: GardenMap, at: WorldCoord, dir: Direction, object: GardenObject) !?WorldCoord {
        const neighbor_coord: WorldCoord = switch (dir) {
            .left => .{ .x = at.x - 1, .y = at.y },
            .right => .{ .x = at.x + 1, .y = at.y },
            .up => .{ .x = at.x, .y = at.y - 1 },
            .down => .{ .x = at.x, .y = at.y + 1 },
        };
        const local_coord = try self.worldToMapCoord(neighbor_coord);
        if (self.map.get(local_coord)) |obj|
            if (obj == object) return neighbor_coord;
        return null;
    }

    pub fn printMap(self: GardenMap) void {
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                if (self.get(x, y)) |obj| {
                    switch (obj) {
                        .Path => print(".", .{}),
                        .Rock => print("#", .{}),
                    }
                }
            }
            print("\n", .{});
        }
    }

    pub fn printWorldMap(self: GardenMap, x1: isize, y1: isize, x2: isize, y2: isize) !void {
        try expect(x1 < x2 and y1 < y2);

        var y = y1;
        while (y < y2) : (y += 1) {
            var x = x1;
            while (x < x2) : (x += 1) {
                const m = try self.worldToMapCoord(.{ .x = x, .y = y });
                if (self.get(m.x, m.y)) |obj| {
                    switch (obj) {
                        .Path => print(".", .{}),
                        .Rock => print("#", .{}),
                    }
                }
            }
            print("\n", .{});
        }
    }

    pub fn worldToMapCoord(self: GardenMap, world: WorldCoord) !MapCoord {
        return .{
            .x = @as(usize, @intCast(try std.math.mod(isize, world.x, @as(isize, @intCast(self.width))))),
            .y = @as(usize, @intCast(try std.math.mod(isize, world.y, @as(isize, @intCast(self.height))))),
        };
    }
};
