const std = @import("std");
const print = std.debug.print;

const idRange = struct { min: u8, max: u8 };

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
        var elf_list = std.mem.split(u8, line, ",");

        const elf1_ids = elf_list.next().?;
        const elf2_ids = elf_list.next().?;

        var elf1_range_list = std.mem.split(u8, elf1_ids, "-");
        var elf2_range_list = std.mem.split(u8, elf2_ids, "-");

        const elf1_range = idRange{
            .min = try std.fmt.parseInt(u8, elf1_range_list.next().?, 10),
            .max = try std.fmt.parseInt(u8, elf1_range_list.next().?, 10),
        };
        const elf2_range = idRange{
            .min = try std.fmt.parseInt(u8, elf2_range_list.next().?, 10),
            .max = try std.fmt.parseInt(u8, elf2_range_list.next().?, 10),
        };

        print("{}-{}, {}-{}", .{ elf1_range.min, elf1_range.max, elf2_range.min, elf2_range.max });

        if ((elf1_range.min <= elf2_range.min and elf1_range.max >= elf2_range.max) or
            (elf1_range.min >= elf2_range.min and elf1_range.max <= elf2_range.max))
        {
            total += 1;
            print(" overlap", .{});
        }
        print("\n", .{});
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
