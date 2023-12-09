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

        // while (line_tok.next()) |t| {
        //     print("{s} ", .{t});
        // }
        print("{s} {s} {s}\n", .{ nodes[0], nodes[1], nodes[2] });
    }

    // Find steps from AAA to ZZZ
    print("\nFinding Path\n", .{});
    var total_steps: usize = 0;
    var next_node: TurnSymbol = .{ 'A', 'A', 'A' };
    var dir_i: usize = 0;

    while (!std.mem.eql(u8, &next_node, "ZZZ")) {
        if (turn_map.getEntry(next_node)) |entry| {
            total_steps += 1;
            print("Step {d:3}: {s} =>", .{ total_steps, next_node });

            next_node = switch (dir_list[dir_i]) {
                'R' => entry.value_ptr.next_right,
                'L' => entry.value_ptr.next_left,
                else => |d| {
                    print("ERROR: Bad direction {c}.\n", .{d});
                    break;
                },
            };

            dir_i = (dir_i + 1) % dir_list.len;

            print(" {s}\n", .{next_node});
        } else {
            print("ERROR: Could not find {s} in map.\n", .{next_node});
            break;
        }
    }

    print("Total Steps: {}\n", .{total_steps});
}

const TurnSymbol = [3]u8;

const TurnNode = struct {
    next_left: TurnSymbol,
    next_right: TurnSymbol,
};
