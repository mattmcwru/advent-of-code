const std = @import("std");

// this is broke so fix before using...

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // const args = try std.process.argsAlloc(std.heap.page_allocator);
    // defer std.process.argsFree(std.heap.page_allocator, args);

    // if (args.len < 2) {
    //     std.debug.print("Error: Missing file argument\n\n", .{});
    //     std.debug.print("Usage: zig run part1.zig -- <filename>\n", .{});
    //     return;
    // }
    // const fileName = args[1];

    const fileName = try getFileNameFromArgs();
    try stdout.print("{s}\n", .{fileName});

    // var file = try std.fs.cwd().openFile(fileName.?, .{});
    // defer file.close();

    // var buf_reader = std.io.bufferedReader(file.reader());
    // var in_stream = buf_reader.reader();

    // var buf: [1024]u8 = undefined;
    // while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
    //     try stdout.print("{s}\n", .{line});
    // }
}

pub fn getFileNameFromArgs() ![]const u8 {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        std.debug.print("Error: Missing file argument\n\n", .{});
        std.debug.print("Usage: zig run part1.zig -- <filename>\n", .{});
        return "";
    }
    std.debug.print("{s}\n", args[1]);

    const fileName = args[1];
    return fileName;
}
