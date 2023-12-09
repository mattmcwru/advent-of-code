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

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    var dir_list: []u8 = undefined;
    defer allocator.free(dir_list);

    // Get the direction list
    if (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        dir_list = try allocator.dupe(u8, line);
        print("{s}\n", .{dir_list});
    }

    var turn_map = std.AutoHashMap(TurnSymbol, TurnNode).init(allocator);
    defer turn_map.deinit();

    var path_list = std.ArrayList(PathNode).init(allocator);
    defer path_list.deinit();

    // Get the map nodes
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (line.len == 0) continue; // Skip blank line
        print("{s} ", .{line});

        // Parse the line
        var line_tok = std.mem.tokenizeAny(u8, line, " =(,)");

        var nodes: [3]TurnSymbol = undefined;
        {
            var i: usize = 0;
            while (line_tok.next()) |t| {
                std.mem.copyForwards(u8, &nodes[i], t);
                i += 1;
            }
        }

        // Add the node to the map
        try turn_map.put(nodes[0], .{ .next_left = nodes[1], .next_right = nodes[2] });

        // If this is a starting node then add it to the path list
        if (nodes[0][2] == 'A') {
            try path_list.append(PathNode{ .starting = nodes[0], .current = nodes[0], .distance = 0 });
        }

        print("{s} {s} {s}\n", .{ nodes[0], nodes[1], nodes[2] });
    }

    // Find length of each path
    for (path_list.items) |*path| {
        print("\nFinding Path for {s}\n", .{path.*.starting});

        var dir_i: usize = 0;
        var path_end_found: bool = false;

        while (!path_end_found) {
            path_end_found = true; // we are hopeful

            path.*.distance += 1;
            print("Step {d:3}: {c} :", .{ path.*.distance, dir_list[dir_i] });

            if (turn_map.getEntry(path.*.current)) |entry| {
                print(" {s} =>", .{path.*.current});

                path.*.current = switch (dir_list[dir_i]) {
                    'R' => entry.value_ptr.next_right,
                    'L' => entry.value_ptr.next_left,
                    else => |d| {
                        print("\nERROR: Bad direction {c}.\n", .{d});
                        break;
                    },
                };

                // Check for ending node
                if (path.*.current[2] != 'Z') path_end_found = false;

                dir_i = (dir_i + 1) % dir_list.len;
                print(" {s}\n", .{path.*.current});
            } else {
                print("\nERROR: Could not find {s} in map.\n", .{path.*.current});
                break;
            }
        }
        print("\n", .{});
    }

    // Compute the total path steps by finding the least common multiple of all path lengths
    var total_steps: usize = 1; // 1 is pass-thru for lcm
    for (path_list.items) |entry| {
        print("Total Steps for Path {s} => {s}: {}\n", .{ entry.starting, entry.current, entry.distance });
        total_steps = lcm(total_steps, entry.distance);
    }

    print("\nTotal Steps: {}\n", .{total_steps});
}

// Least Common Multiple
pub fn lcm(m: usize, n: usize) usize {
    return m / std.math.gcd(m, n) * n;
}

const TurnSymbol = [3]u8;

const TurnNode = struct {
    next_left: TurnSymbol,
    next_right: TurnSymbol,
};

const PathNode = struct {
    starting: TurnSymbol,
    current: TurnSymbol,
    distance: usize,
};
