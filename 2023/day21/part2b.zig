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
    //try map.printWorldMap(-11, -11, 22, 22);

    // Go here to figure this garbage out: https://youtu.be/9UOMZSL0JTg?si=OZ_grUB7vSH_Rpms

    // Find number of plots reached by each step
    const steps: usize = 26501365;

    try expect(map_width == map_height); // map should be square
    try expect(start_point.x == map_width / 2); // start in center

    const squares_to_edge = (steps - map_width / 2) / map_width;
    const grid_width = (steps / map_width) - 1;
    const odd_grids = std.math.pow(usize, @divFloor(grid_width, 2) * 2 + 1, 2);
    const even_grids = std.math.pow(usize, @divFloor(grid_width + 1, 2) * 2, 2);

    print("Map Width/Height: {}/{}\n", .{ map_width, map_height });
    print("Start Point: ({},{})\n", .{ start_point.x, start_point.y });
    print("Steps: {}\n", .{steps});
    print("Squares To Edge: {}\n", .{squares_to_edge});
    print("Grid Width: {}\n", .{grid_width});
    print("Odd Grids:  {}\n", .{odd_grids});
    print("Even Grids: {}\n", .{even_grids});

    const odd_reached = try map.plotsReached(start_point, map_width * 2 + 1);
    const even_reached = try map.plotsReached(start_point, map_width * 2);
    print("Reached Odd:  {}\n", .{odd_reached});
    print("Reached Even: {}\n", .{even_reached});

    const tc_reached = try map.plotsReached(.{ .x = map_width / 2, .y = map_height - 1 }, map_height - 1);
    const bc_reached = try map.plotsReached(.{ .x = map_width / 2, .y = 0 }, map_height - 1);
    const lc_reached = try map.plotsReached(.{ .x = map_width - 1, .y = map_height / 2 }, map_width - 1);
    const rc_reached = try map.plotsReached(.{ .x = 0, .y = map_height / 2 }, map_width - 1);

    print("Reached Top Corner:    {}\n", .{tc_reached});
    print("Reached Bottom Corner: {}\n", .{bc_reached});
    print("Reached Left Corner:   {}\n", .{lc_reached});
    print("Reached Right Corner:  {}\n", .{rc_reached});

    const str_reached = try map.plotsReached(.{ .x = 0, .y = map_height - 1 }, map_width / 2 - 1);
    const stl_reached = try map.plotsReached(.{ .x = map_width - 1, .y = map_height - 1 }, map_width / 2 - 1);
    const sbr_reached = try map.plotsReached(.{ .x = 0, .y = 0 }, map_width / 2 - 1);
    const sbl_reached = try map.plotsReached(.{ .x = map_width - 1, .y = 0 }, map_width / 2 - 1);

    print("Reached Top-Right Small Edge:    {}\n", .{str_reached});
    print("Reached Top-Left Small Edge:     {}\n", .{stl_reached});
    print("Reached Bottom-Right Small Edge: {}\n", .{sbr_reached});
    print("Reached Bottom-Left Small Edge:  {}\n", .{sbl_reached});

    const ltr_reached = try map.plotsReached(.{ .x = 0, .y = map_height - 1 }, (map_width * 3) / 2 - 1);
    const ltl_reached = try map.plotsReached(.{ .x = map_width - 1, .y = map_height - 1 }, (map_width * 3) / 2 - 1);
    const lbr_reached = try map.plotsReached(.{ .x = 0, .y = 0 }, (map_width * 3) / 2 - 1);
    const lbl_reached = try map.plotsReached(.{ .x = map_width - 1, .y = 0 }, (map_width * 3) / 2 - 1);

    print("Reached Top-Right Large Edge:    {}\n", .{ltr_reached});
    print("Reached Top-Left Large Edge:     {}\n", .{ltl_reached});
    print("Reached Bottom-Right Large Edge: {}\n", .{lbr_reached});
    print("Reached Bottom-Left Large Edge:  {}\n", .{lbl_reached});

    var total_reached = (odd_reached * odd_grids) + (even_reached * even_grids);
    total_reached += tc_reached + bc_reached + lc_reached + rc_reached;
    total_reached += (grid_width + 1) * (str_reached + stl_reached + sbr_reached + sbl_reached);
    total_reached += (grid_width) * (ltr_reached + ltl_reached + lbr_reached + lbl_reached);

    print("Total Reached: {}\n", .{total_reached});
}

const SearchNode = struct {
    location: GardenMap.MapCoord,
    steps_remaining: usize,
};

const SearchWorldNode = struct {
    location: GardenMap.WorldCoord,
    steps_remaining: usize,
};

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

    pub fn plotsReached(self: GardenMap, start_point: MapCoord, steps: usize) !usize {
        var search_queue = std.ArrayList(SearchNode).init(self.allocator);
        defer search_queue.deinit();

        // Add starting position to search queue
        try search_queue.append(.{
            .location = .{
                .x = start_point.x,
                .y = start_point.y,
            },
            .steps_remaining = steps,
        });

        var plots_reached = std.AutoHashMap(GardenMap.MapCoord, void).init(self.allocator);
        defer plots_reached.deinit();

        var seen_nodes = std.AutoHashMap(GardenMap.MapCoord, void).init(self.allocator);
        defer seen_nodes.deinit();

        const dirs = [_]GardenMap.Direction{ .left, .right, .up, .down };

        while (search_queue.popOrNull()) |node| {
            if (try std.math.mod(usize, node.steps_remaining, 2) == 0) {
                try plots_reached.put(node.location, {});
            }
            if (node.steps_remaining == 0) {
                continue;
            }

            // Get allowed directions for next step
            for (dirs) |dir| {
                if (self.isNeighbor(node.location, dir, .Path)) |np| {
                    const next_node = SearchNode{ .location = np, .steps_remaining = node.steps_remaining - 1 };
                    if (!seen_nodes.contains(next_node.location)) {
                        try seen_nodes.put(next_node.location, {});
                        try search_queue.insert(0, next_node);
                    }
                }
            }
            //print("Plots reached after step {}: {}\n", .{ steps - node.steps_remaining + 1, plots_reached.items.len });
        }
        //print("Plots reached after step {}: {}\n", .{ steps, plots_reached.items.len - 1 });

        return plots_reached.count();
    }

    pub fn plotsReachedWorld(self: GardenMap, start_point: MapCoord, steps: usize) !usize {
        var search_queue = std.ArrayList(SearchWorldNode).init(self.allocator);
        defer search_queue.deinit();

        // Add starting position to search queue
        try search_queue.append(.{
            .location = .{
                .x = @as(isize, @intCast(start_point.x)),
                .y = @as(isize, @intCast(start_point.y)),
            },
            .steps_remaining = steps,
        });

        var plots_reached = std.AutoHashMap(GardenMap.WorldCoord, void).init(self.allocator);
        defer plots_reached.deinit();

        var seen_nodes = std.AutoHashMap(GardenMap.WorldCoord, void).init(self.allocator);
        defer seen_nodes.deinit();

        const dirs = [_]GardenMap.Direction{ .left, .right, .up, .down };

        while (search_queue.popOrNull()) |node| {
            if (try std.math.mod(usize, node.steps_remaining, 2) == 0) {
                try plots_reached.put(node.location, {});
            }
            if (node.steps_remaining == 0) {
                continue;
            }

            // Get allowed directions for next step
            for (dirs) |dir| {
                if (try self.isWorldNeighbor(node.location, dir, .Path)) |np| {
                    const next_node = SearchWorldNode{ .location = np, .steps_remaining = node.steps_remaining - 1 };
                    if (!seen_nodes.contains(next_node.location)) {
                        try seen_nodes.put(next_node.location, {});
                        try search_queue.insert(0, next_node);
                    }
                }
            }
            //print("Plots reached after step {}: {}\n", .{ steps - node.steps_remaining + 1, plots_reached.items.len });
        }
        //print("Plots reached after step {}: {}\n", .{ steps, plots_reached.items.len - 1 });

        return plots_reached.items.len;
    }
};
