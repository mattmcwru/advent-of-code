const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const filename = try getFileNameFromArgs(allocator);
    defer allocator.free(filename);

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var map = std.AutoHashMap(u8, void).init(allocator);
    defer map.deinit();

    var total: u32 = 0;

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        //print("{s}\n", .{line});

        std.debug.assert(@mod(line.len, 2) == 0); // expect even number of characters

        const len_mid = line.len / 2;
        const first_container = line[0..len_mid];
        const second_container = line[len_mid..];

        print("{s} | {s}", .{ first_container, second_container });

        // Put the first container into hash map so searching by key is easier
        map.clearRetainingCapacity();
        for (first_container) |c| {
            try map.put(c, {});
        }

        // Search
        var dup_item: ?u8 = null;
        for (second_container) |c| {
            if (map.contains(c)) {
                dup_item = c;
                break;
            }
        }

        std.debug.assert(dup_item != null);

        const item_pri = getPri(dup_item.?);

        print("  <{c}, {}>\n", .{ dup_item.?, item_pri });

        total += item_pri;
    }

    print("\nTotal: {}\n", .{total});
}

// Must free returned string
fn getFileNameFromArgs(allocator: std.mem.Allocator) ![]u8 {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Error: Missing file argument\n\n", .{});
        std.debug.print("Usage: zig run part1.zig -- <filename>\n", .{});
        return error.FileNotFound;
    }

    const filename = try allocator.alloc(u8, args[1].len);
    errdefer allocator.free(filename);

    std.mem.copy(u8, filename, args[1]);

    return filename;
}

fn getPri(char: u8) u32 {
    return switch (char) {
        'a'...'z' => 1 + char - 'a',
        'A'...'Z' => 27 + char - 'A',
        else => 0,
    };
}
