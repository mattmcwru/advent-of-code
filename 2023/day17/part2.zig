const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

const Position = struct { x: usize, y: usize };
const Direction = enum { up, down, left, right, none };
const Location = struct {
    pos: Position,
    dir: Direction,
    steps: usize,

    pub fn init(x: usize, y: usize, dir: Direction, steps: usize) Location {
        return .{
            .pos = Position{ .x = x, .y = y },
            .dir = dir,
            .steps = steps,
        };
    }

    pub fn eql(a: Location, b: Location) bool {
        return a.pos.x == b.pos.x and a.pos.y == b.pos.y and a.dir == b.dir and a.steps == b.steps;
    }
};

const Map = struct {
    data: [150][150]u4,
    width: usize,
    height: usize,
    allocator: std.mem.Allocator,

    comptime maxSteps: usize = 10,
    comptime minSteps: usize = 4,

    const PathNode = struct {
        location: Location,
        from_location: ?Location,
        score: usize,

        pub fn nodeLessThan(_: void, a: PathNode, b: PathNode) std.math.Order {
            return std.math.order(a.score, b.score);
        }
    };

    const PathList = std.ArrayList(PathNode);

    pub fn init(allocator: std.mem.Allocator) Map {
        return .{
            .data = .{.{0} ** 150} ** 150,
            .width = 0,
            .height = 0,
            .allocator = allocator,
        };
    }

    pub fn insert(self: *Map, x: usize, y: usize, d: u4) !void {
        try expect(x < 150 and y < 150);
        self.data[y][x] = d;
        self.width = @max(self.width, x + 1);
        self.height = @max(self.height, y + 1);
    }

    pub fn print_map(self: Map) void {
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                print("{}", .{self.data[y][x]});
            }
            print("\n", .{});
        }
    }

    pub fn pathSearch(self: Map, starting_pos: Position, ending_pos: Position) !PathList {
        // Priority Queue for search
        var search_queue = std.PriorityQueue(PathNode, void, PathNode.nodeLessThan).init(self.allocator, {});
        defer search_queue.deinit();

        // List of items in priority queue (this is a work around for the broken update function in the std.PriorityQueue)
        var in_queue = std.AutoHashMap(Location, void).init(self.allocator);
        defer in_queue.deinit();

        // List of completed nodes
        var done_list = std.AutoHashMap(Location, PathNode).init(self.allocator);
        defer done_list.deinit();

        var starting_location = Location.init(starting_pos.x, starting_pos.y, .none, 0);
        var ending_location: Location = undefined;

        // Add the starting node to the queue
        try search_queue.add(.{
            .location = starting_location,
            .from_location = null,
            .score = 0,
        });
        try in_queue.put(starting_location, {});

        // Process queue
        while (search_queue.removeOrNull()) |node| {
            if (done_list.contains(node.location)) {

                //if (done_list.get(node.location)) |dn| {
                // if (dn.score >= node.score)
                //     print(" Node In Done: {},{}  Score: [{} {s} {}] [{} {s} {}]\n", .{
                //         node.location.pos.x,
                //         node.location.pos.y,
                //         node.score,
                //         @tagName(node.location.dir),
                //         node.location.steps,
                //         dn.score,
                //         @tagName(dn.location.dir),
                //         dn.location.steps,
                //     });
                continue;
            }

            // Add removed node to done
            try done_list.put(node.location, node);

            // print("DQ> Pos: {},{} Dir: {s:5} From: {any},{any} Score: {}\n", .{
            //     node.location.pos.x,
            //     node.location.pos.y,
            //     @tagName(node.location.dir),
            //     if (node.from_pos) |pos| pos.x else null,
            //     if (node.from_pos) |pos| pos.y else null,
            //     node.score,
            // });

            // If removed node is the ending position then stop
            if (ending_pos.x == node.location.pos.x and ending_pos.y == node.location.pos.y) {
                ending_location = node.location;
                print("Ending Node found!\n", .{});
                break;
            }

            // Remove from in-queue list
            if (!in_queue.remove(node.location)) {
                //print("Remove: {any} was not in in-queue to remove\n", .{node.location.pos});
            }

            // Find neighbors
            const neighbors = self.findNeighbors(node.location);
            for (neighbors) |neighbor_or_null| {
                if (neighbor_or_null) |neighbor| {
                    // Ignore neighbors in the done list
                    if (done_list.contains(neighbor)) {
                        //print(" Neighbor In Done: {},{}\n", .{ neighbor.pos.x, neighbor.pos.y });
                        continue;
                    }

                    // If neighbor still in queue
                    if (in_queue.contains(neighbor)) {
                        //print(" Neighbor In Queue: {},{}\n", .{ neighbor.pos.x, neighbor.pos.y });
                    }

                    // Add the neighbor to the queue
                    var node_score = node.score + self.data[neighbor.pos.y][neighbor.pos.x];
                    try in_queue.put(neighbor, {});
                    try search_queue.add(.{
                        .location = neighbor,
                        .from_location = node.location,
                        .score = node_score,
                    });
                    //print("  Added to Queue: {},{} Score: {}\n", .{ neighbor.pos.x, neighbor.pos.y, node_score });
                }
            }
        }

        // Backtrack the found path and put into the output list
        var path_list = PathList.init(self.allocator);
        errdefer path_list.deinit();

        var path_location = ending_location;
        var start_found = false;
        while (!start_found) {
            if (done_list.get(path_location)) |path_node| {
                try path_list.insert(0, path_node);

                if (path_location.pos.x == starting_pos.x and path_location.pos.y == starting_pos.y) {
                    start_found = true;
                } else {
                    path_location = path_node.from_location.?;
                }
            } else {
                print("Missing path node for {any}\n", .{path_location});
                @panic("Failed during pathSearch()");
            }
        }

        print("Path List\n", .{});

        for (path_list.items, 0..) |node, i| {
            print("{}: {any}\n", .{ i, node });
        }

        return path_list;
    }

    // Find neighbors based on position and travel direction
    pub fn findNeighbors(self: Map, loc: Location) [4]?Location {
        const x = loc.pos.x;
        const y = loc.pos.y;
        const steps = loc.steps;

        return switch (loc.dir) {
            .up => .{
                if (x > 0 and steps >= self.minSteps) Location.init(x - 1, y, .left, 1) else null,
                if (x < self.width - 1 and steps >= self.minSteps) Location.init(x + 1, y, .right, 1) else null,
                if (y > 0 and steps < self.maxSteps) Location.init(x, y - 1, .up, steps + 1) else null,
                null,
            },
            .down => .{
                if (x > 0 and steps >= self.minSteps) Location.init(x - 1, y, .left, 1) else null,
                if (x < self.width - 1 and steps >= self.minSteps) Location.init(x + 1, y, .right, 1) else null,
                if (y < self.height - 1 and steps < self.maxSteps) Location.init(x, y + 1, .down, steps + 1) else null,
                null,
            },
            .left => .{
                if (x > 0 and steps < self.maxSteps) Location.init(x - 1, y, .left, steps + 1) else null,
                if (y > 0 and steps >= self.minSteps) Location.init(x, y - 1, .up, 1) else null,
                if (y < self.height - 1 and steps >= self.minSteps) Location.init(x, y + 1, .down, 1) else null,
                null,
            },
            .right => .{
                if (x < self.width - 1 and steps < self.maxSteps) Location.init(x + 1, y, .right, steps + 1) else null,
                if (y > 0 and steps >= self.minSteps) Location.init(x, y - 1, .up, 1) else null,
                if (y < self.height - 1 and steps >= self.minSteps) Location.init(x, y + 1, .down, 1) else null,
                null,
            },
            .none => .{
                if (x > 0) Location.init(x - 1, y, .left, 1) else null,
                if (x < self.width - 1) Location.init(x + 1, y, .right, 1) else null,
                if (y > 0) Location.init(x, y - 1, .up, 1) else null,
                if (y < self.height - 1) Location.init(x, y + 1, .down, 1) else null,
            },
        };
    }
};

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

    var line_num: usize = 0;

    var map = Map.init(allocator);

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        for (line, 0..) |c, i| {
            const s = [_]u8{c};
            try map.insert(i, line_num, try std.fmt.parseInt(u4, &s, 10));
        }
        line_num += 1;
    }

    const start_pos = Position{ .x = 0, .y = 0 };
    const final_pos = Position{ .x = map.width - 1, .y = map.height - 1 };

    const path_list = try map.pathSearch(start_pos, final_pos);
    defer path_list.deinit();

    map.print_map();

    print("\n", .{});

    var path_hashmap = std.AutoHashMap(Position, Map.PathNode).init(allocator);
    defer path_hashmap.deinit();

    var heat_loss: usize = 0;
    for (path_list.items) |p| {
        try path_hashmap.put(p.location.pos, p);
        if (!(p.location.pos.y == start_pos.y and p.location.pos.x == start_pos.x))
            heat_loss += map.data[p.location.pos.y][p.location.pos.x];
    }

    for (0..map.height) |y| {
        for (0..map.width) |x| {
            if (path_hashmap.get(Position{ .x = x, .y = y })) |node| {
                switch (node.location.dir) {
                    .up => print("^", .{}),
                    .down => print("v", .{}),
                    .left => print("<", .{}),
                    .right => print(">", .{}),
                    .none => print("O", .{}),
                }
            } else {
                print(".", .{});
            }
        }
        print("\n", .{});
    }

    print("\nHeat Loss: {}\n", .{heat_loss});
}
