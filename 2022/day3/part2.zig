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

    var map_m1 = std.AutoHashMap(u8, void).init(allocator);
    defer map_m1.deinit();

    var map_m2 = std.AutoHashMap(u8, void).init(allocator);
    defer map_m2.deinit();

    var total: u32 = 0;
    var group_member: u8 = 0;

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        print("{s}  | ", .{line});

        if (group_member == 0) {
            // Put all characters in hash map for the first group member
            map_m1.clearRetainingCapacity();
            for (line) |c| {
                try map_m1.put(c, {});
                print("{c},", .{c});
            }
            print(" ({})\n", .{map_m1.count()});
        }

        if (group_member == 1) {
            // Put only second member characters shared with first member in hash map
            map_m2.clearRetainingCapacity();
            for (line) |c| {
                if (map_m1.contains(c)) {
                    try map_m2.put(c, {});
                    print("{c},", .{c});
                }
            }
            print(" ({})\n", .{map_m2.count()});
        }

        if (group_member == 2) {
            var dup_item: ?u8 = null;

            // Just directly search for matching characters with second member
            for (line) |c| {
                if (map_m2.contains(c)) {
                    dup_item = c;
                    break;
                }
            }

            std.debug.assert(dup_item != null);
            const item_pri = getPri(dup_item.?);
            total += item_pri;

            print("{c}, {}\n", .{ dup_item.?, item_pri });
        }

        group_member = @mod(group_member + 1, 3);
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
