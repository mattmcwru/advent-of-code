const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const assert = std.debug.assert;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

// | is a vertical pipe connecting north and south.
// - is a horizontal pipe connecting east and west.
// L is a 90-degree bend connecting north and east.
// J is a 90-degree bend connecting north and west.
// 7 is a 90-degree bend connecting south and west.
// F is a 90-degree bend connecting south and east.
// . is ground; there is no pipe in this tile.
// S is the starting position of the animal; there is a pipe on this tile, but your sketch doesn't show what shape the pipe has.

const MapCoord = struct {
    const T = usize;
    map_x: T,
    map_y: T,

    const Op = enum { sub_x, sub_y, add_x, add_y };

    pub fn doOp(self: MapCoord, value: T, op: Op) !MapCoord {
        return switch (op) {
            .add_x => .{ .map_x = try std.math.add(T, self.map_x, value), .map_y = self.map_y },
            .add_y => .{ .map_x = self.map_x, .map_y = try std.math.add(T, self.map_y, value) },
            .sub_x => .{ .map_x = try std.math.sub(T, self.map_x, value), .map_y = self.map_y },
            .sub_y => .{ .map_x = self.map_x, .map_y = try std.math.sub(T, self.map_y, value) },
        };
    }
};

const MapNode = struct {
    map_x: usize,
    map_y: usize,
    distance: usize,
    connector: Connector,
    segment: LineSegment,

    const LineSegment = enum {
        start_point,
        end_point,
        v_segment,
        h_segment,
    };

    const Connector = enum(u8) {
        v_pipe = '|',
        h_pipe = '-',
        ne_bend = 'L',
        nw_bend = 'J',
        sw_bend = '7',
        se_bend = 'F',
        start = 'S',

        const Direction = enum(u4) {
            none = 0,
            north = 1,
            south = 2,
            north_south = 3,
            west = 4,
            north_west = 5,
            south_west = 6,
            north_south_west = 7,
            east = 8,
            north_east = 9,
            south_east = 10,
            north_south_east = 11,
            west_east = 12,
            north_west_east = 13,
            south_west_east = 14,
            north_south_west_east = 15,

            pub fn getOppositeDir(self: Direction) Direction {
                return @enumFromInt(((@intFromEnum(self) & 0b1010) >> 1) | ((@intFromEnum(self) & 0b0101) << 1));
            }
        };

        // Could use @enumFromInt() instead but it throws a panic with undefined input.
        // This seems like a safer way to check for unknown input if the error is caught and delt with.
        pub fn init(symbol: u8) !Connector {
            return switch (symbol) {
                '|' => .v_pipe,
                '-' => .h_pipe,
                'L' => .ne_bend,
                'J' => .nw_bend,
                '7' => .sw_bend,
                'F' => .se_bend,
                'S' => .start,
                else => error.BadSymbol,
            };
        }

        pub fn getAllowedDir(self: Connector) Direction {
            return switch (self) {
                .v_pipe => .north_south,
                .h_pipe => .west_east,
                .ne_bend => .north_east,
                .nw_bend => .north_west,
                .sw_bend => .south_west,
                .se_bend => .south_east,
                .start => .north_south_west_east,
            };
        }

        pub fn getSegmentType(self: Connector, next_dir: Direction, prev_dir: Direction) LineSegment {
            return switch (self) {
                .v_pipe => .v_segment,
                .h_pipe => .h_segment,
                .start => if (next_dir == .north or prev_dir == .south) .start_point else .end_point,
                .ne_bend, .nw_bend => .start_point,
                .se_bend, .sw_bend => .end_point,
            };
        }

        pub fn isPipeConnected(self: Connector, pipe: Connector, direction: Direction) bool {
            const from_dir = @intFromEnum(self.getAllowedDir());
            const to_dir = @intFromEnum(pipe.getAllowedDir().getOppositeDir());
            const dir_mask = @intFromEnum(direction);

            return if (((from_dir & dir_mask) & to_dir) != 0) true else false;
        }
    };
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

    var map = std.AutoArrayHashMap(MapCoord, MapNode).init(allocator);
    defer map.deinit();

    var start_pos: MapCoord = undefined;
    var line_num: usize = 0;
    var grid_max_x: usize = 0;
    var grid_max_y: usize = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        for (line, 0..) |c, i| {
            print("{c}", .{c});
            grid_max_x = @max(grid_max_x, i);

            if (c == '.') continue; // Skip ground

            if (c == 'S') { // Mark starting node (should only be one)
                start_pos = .{ .map_x = i, .map_y = line_num };
            }

            // Add node to map
            try map.put(.{ .map_x = i, .map_y = line_num }, .{
                .map_x = i,
                .map_y = line_num,
                .distance = undefined,
                .connector = try MapNode.Connector.init(c),
                .segment = undefined,
            });
        }

        print("\n", .{});
        line_num += 1;
    }
    grid_max_x += 1;
    grid_max_y = line_num;
    print("\n", .{});

    // Find loop nodes
    var curr_pos = start_pos;
    var prev_dir: MapNode.Connector.Direction = .none;
    var distance: usize = 0;

    var loop_nodes = std.AutoArrayHashMap(MapCoord, MapNode).init(allocator);
    defer loop_nodes.deinit();

    while (true) : (distance += 1) {
        if (map.getPtr(curr_pos)) |node| {
            //print("{} {s}: {},{}  {s}\n", .{ distance, @tagName(prev_dir), node.*.map_x, node.*.map_y, @tagName(node.*.connector) });

            // Stop if arrived back at start
            if (prev_dir != .none and node.*.connector == .start) break;

            // Save the node's distance from start
            node.*.distance = distance;

            // Get next position
            const next_dir = try findPipeDir(curr_pos, prev_dir, &map);

            // Assign the segment type based on the movement direction
            node.*.segment = node.*.connector.getSegmentType(next_dir.direction, prev_dir);

            // Add node to loop path
            try loop_nodes.put(curr_pos, node.*);

            // Update previous position
            curr_pos = next_dir.map_coord;
            prev_dir = next_dir.direction.getOppositeDir();
        } else {
            @panic("Node not found\n");
        }
    }

    // Find loop's neighbor nodes
    var neighbor_nodes = std.AutoArrayHashMap(MapCoord, void).init(allocator);
    defer neighbor_nodes.deinit();

    for (loop_nodes.keys()) |coord| {
        if (coord.map_x > 0 and !loop_nodes.contains(.{ .map_x = coord.map_x - 1, .map_y = coord.map_y }))
            try neighbor_nodes.put(.{ .map_x = coord.map_x - 1, .map_y = coord.map_y }, {});
        if (coord.map_x < grid_max_x - 1 and !loop_nodes.contains(.{ .map_x = coord.map_x + 1, .map_y = coord.map_y }))
            try neighbor_nodes.put(.{ .map_x = coord.map_x + 1, .map_y = coord.map_y }, {});
        if (coord.map_y > 0 and !loop_nodes.contains(.{ .map_x = coord.map_x, .map_y = coord.map_y - 1 }))
            try neighbor_nodes.put(.{ .map_x = coord.map_x, .map_y = coord.map_y - 1 }, {});
        if (coord.map_y < grid_max_y - 1 and !loop_nodes.contains(.{ .map_x = coord.map_x, .map_y = coord.map_y + 1 }))
            try neighbor_nodes.put(.{ .map_x = coord.map_x, .map_y = coord.map_y + 1 }, {});
    }

    // Note: This flood fill worked on outer parts but did not get inner nodes...
    //
    // // Find the outer nodes
    // var outer_nodes = std.AutoArrayHashMap(MapCoord, void).init(allocator);
    // defer outer_nodes.deinit();
    // var stack = std.ArrayList(MapCoord).init(allocator);
    // defer stack.deinit();

    // // Starting fill from top,left (this is wrong if that position is used by loop)
    // try stack.append(.{ .map_x = 0, .map_y = 0 });

    // while (stack.items.len > 0) {
    //     const coord = stack.pop();

    //     // Skip if on loop or already marked as outer
    //     if (loop_nodes.contains(.{ .map_x = coord.map_x, .map_y = coord.map_y }) or
    //         outer_nodes.contains(.{ .map_x = coord.map_x, .map_y = coord.map_y }))
    //         continue;

    //     // Add node to outer list
    //     try outer_nodes.put(coord, {});

    //     // Add neighbors to list
    //     if (coord.map_x > 0)
    //         try stack.append(.{ .map_x = coord.map_x - 1, .map_y = coord.map_y });
    //     if (coord.map_x < grid_max_x - 1)
    //         try stack.append(.{ .map_x = coord.map_x + 1, .map_y = coord.map_y });
    //     if (coord.map_y > 0)
    //         try stack.append(.{ .map_x = coord.map_x, .map_y = coord.map_y - 1 });
    //     if (coord.map_y < grid_max_y - 1)
    //         try stack.append(.{ .map_x = coord.map_x, .map_y = coord.map_y + 1 });
    // }

    // Find the inner nodes (via raycasting)
    var inner_nodes = std.AutoArrayHashMap(MapCoord, void).init(allocator);
    defer inner_nodes.deinit();

    for (0..grid_max_y) |y| {
        var loop_node_count: usize = 0;

        for (0..grid_max_x) |x| {
            if (loop_nodes.get(.{ .map_x = x, .map_y = y })) |node| {
                if (node.segment == .start_point or node.segment == .v_segment)
                    loop_node_count += 1;
                continue;
            }

            // Inner nodes will have crossed an odd number of segments
            if (@mod(loop_node_count, 2) == 1) {
                try inner_nodes.put(.{ .map_x = x, .map_y = y }, {});
            }
        }
    }

    // Print the map
    print("\n", .{});
    for (0..grid_max_y) |y| {
        for (0..grid_max_x) |x| {
            if (loop_nodes.get(.{ .map_x = x, .map_y = y })) |node| {
                const color_code: u8 = if (node.connector == .start) 32 else if (node.distance < distance / 2) 31 else 34; // Green, Red or Blue
                print("\x1B[1;{}m{c}\x1B[0m", .{ color_code, @intFromEnum(node.connector) });

                // switch (node.segment) {
                //     .start_point => print("\x1B[1;{}m{c}\x1B[0m", .{ color_code, 'O' }),
                //     .end_point => print("\x1B[1;{}m{c}\x1B[0m", .{ color_code, '^' }),
                //     else => print("\x1B[1;{}m{c}\x1B[0m", .{ color_code, @intFromEnum(node.connector) }),
                // }

                //print(" ", .{});

                // } else if (neighbor_nodes.contains(.{ .map_x = x, .map_y = y })) {
                //     if (outer_nodes.contains(.{ .map_x = x, .map_y = y })) {
                //         print("o", .{});
                //     } else {
                //         print("X", .{});
                //     }
                // } else if (outer_nodes.contains(.{ .map_x = x, .map_y = y })) {
                //     print("O", .{});
            } else if (inner_nodes.contains(.{ .map_x = x, .map_y = y })) {
                print("I", .{});
            } else {
                print(".", .{});
                //print(" ", .{});
            }
        }
        print("\n", .{});
    }
    print("\n", .{});

    print("Grid Size: {}, {}\n", .{ grid_max_x, grid_max_y });
    print("Distance to farthest point: {}\n", .{distance / 2});
    print("Inner Node Number: {}\n", .{inner_nodes.count()});
}

const PipeDir = struct {
    map_coord: MapCoord,
    direction: MapNode.Connector.Direction,
};

// Find the first direction not already traveled
pub fn findPipeDir(start_pos: MapCoord, prev_dir: MapNode.Connector.Direction, map: *const std.AutoArrayHashMap(MapCoord, MapNode)) !PipeDir {
    const start_node = map.get(start_pos) orelse return error.StartNodeNotFound;

    const dir_list = [_]MapNode.Connector.Direction{ .west, .east, .north, .south };
    const op_list = [_]MapCoord.Op{ .sub_x, .add_x, .sub_y, .add_y };

    for (dir_list, op_list) |dir, op| {
        if (prev_dir != dir) {
            const test_coord = start_pos.doOp(1, op) catch continue;
            if (map.get(test_coord)) |pos| {
                //print("  {},{}  {any}\n", .{ pos.map_x, pos.map_y, pos.connector });
                if (start_node.connector.isPipeConnected(pos.connector, dir))
                    return .{ .map_coord = test_coord, .direction = dir };
            }
        }
    }
    print("Can not find starting direction\n", .{});
    return error.StartingDirectionNotFound;
}

test "usize underflow testing" {
    const a: usize = 2;

    // Test underflow with built-in sub function
    const c = @subWithOverflow(a, a + 1);
    print("\n{} {}\n", .{ c[0], c[1] });

    // Test the error flow control using std.math.sub function
    for (0..6) |i| {
        defer print("\n", .{});
        print("i = {}: b = ", .{i});

        // This line should error for negative numbers and not print
        print("{}", .{std.math.sub(usize, a, i) catch continue});
    }
}
