const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        std.debug.print("Error: Missing file argument\n\n", .{});
        std.debug.print("Usage: zig run part1.zig -- <filename>\n", .{});
        return;
    }
    const fileName = args[1];

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var max_cal: u32 = 0;
    var elf_cal: u32 = 0;
    const spacer = [_][]const u8{ " ", " + " };
    var new_elf: bool = true;

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (line.len == 0) { // Compute elf total
            try stdout.print(" = {}\n", .{elf_cal});
            max_cal = @max(elf_cal, max_cal);
            elf_cal = 0;
            new_elf = true;
        } else { // Add line for current elf
            const cal = try std.fmt.parseInt(u32, line, 10);
            try stdout.print("{s}{}", .{ spacer[if (new_elf) 0 else 1], cal });
            elf_cal += cal;
            new_elf = false;
        }
    }

    // Compute elf totoal for last entry (if missing blank line at end)
    if (!new_elf) {
        try stdout.print(" = {}\n", .{elf_cal});
        max_cal = @max(elf_cal, max_cal);
    }

    try stdout.print("\nTotal: {}\n", .{max_cal});
}
