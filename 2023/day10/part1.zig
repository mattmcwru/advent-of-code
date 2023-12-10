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
    map_x: usize,
    map_y: usize,
};

const MapNode = struct {
    map_x: usize,
    map_y: usize,
    distance: usize,
    connector: Connector,

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

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        for (line, 0..) |c, i| {
            print("{c}", .{c});
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
            });
        }

        print("\n", .{});
        line_num += 1;
    }
    print("\n", .{});

    // Compute distances
    var curr_pos = start_pos;
    var prev_dir: MapNode.Connector.Direction = .none;
    var distance: usize = 0;

    while (true) : (distance += 1) {
        if (map.getPtr(curr_pos)) |node| {
            print("{} {s}: {},{}  {s}\n", .{ distance, @tagName(prev_dir), node.*.map_x, node.*.map_y, @tagName(node.*.connector) });

            // Stop if arrived back at start
            if (prev_dir != .none and node.*.connector == .start) break;

            // Save the node's distance from start
            node.*.distance = distance;

            // Get next position
            const next_dir = try findPipeDir(curr_pos, prev_dir, &map);
            curr_pos = next_dir.map_coord;
            prev_dir = next_dir.direction.getOppositeDir();
        } else {
            @panic("Node not found\n");
        }
    }

    print("Distance to farthest point: {}\n", .{distance / 2});
}

const PipeDir = struct {
    map_coord: MapCoord,
    direction: MapNode.Connector.Direction,
};

// Find the first direction not already traveled
pub fn findPipeDir(start_pos: MapCoord, prev_dir: MapNode.Connector.Direction, map: *const std.AutoArrayHashMap(MapCoord, MapNode)) !PipeDir {
    const start_node = map.get(start_pos) orelse return error.StartNodeNotFound;

    // Test West
    if (prev_dir != .west and start_pos.map_x > 0) {
        const test_coord = .{ .map_x = start_pos.map_x - 1, .map_y = start_pos.map_y };
        if (map.get(test_coord)) |pos| {
            //print("  {},{}  {any}\n", .{ pos.map_x, pos.map_y, pos.connector });
            if (start_node.connector.isPipeConnected(pos.connector, .west))
                return .{ .map_coord = test_coord, .direction = .west };
        }
    }

    // Test North
    if (prev_dir != .north and start_pos.map_y > 0) {
        const test_coord = .{ .map_x = start_pos.map_x, .map_y = start_pos.map_y - 1 };
        if (map.get(test_coord)) |pos| {
            //print("  {},{}  {any}\n", .{ pos.map_x, pos.map_y, pos.connector });
            if (start_node.connector.isPipeConnected(pos.connector, .north))
                return .{ .map_coord = test_coord, .direction = .north };
        }
    }

    // Test East
    if (prev_dir != .east) {
        const test_coord = .{ .map_x = start_pos.map_x + 1, .map_y = start_pos.map_y };
        if (map.get(test_coord)) |pos| {
            //print("  {},{}  {any}\n", .{ pos.map_x, pos.map_y, pos.connector });
            if (start_node.connector.isPipeConnected(pos.connector, .east))
                return .{ .map_coord = test_coord, .direction = .east };
        }
    }

    // Test South
    if (prev_dir != .south) {
        const test_coord = .{ .map_x = start_pos.map_x, .map_y = start_pos.map_y + 1 };
        if (map.get(test_coord)) |pos| {
            //print("  {},{}  {any}\n", .{ pos.map_x, pos.map_y, pos.connector });
            if (start_node.connector.isPipeConnected(pos.connector, .south))
                return .{ .map_coord = test_coord, .direction = .south };
        }
    }

    print("Can not find starting direction\n", .{});
    return error.StartingDirectionNotFound;
}
