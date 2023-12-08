const std = @import("std");

// Must free returned string
pub fn getFileNameFromArgs(allocator: std.mem.Allocator) ![]u8 {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 1) {
        std.debug.print("Error: Missing executable argument\n\n", .{});
        return error.NoExecutableName;
    }

    const exe_name = std.fs.path.basename(args[0]);

    if (args.len < 2) {
        std.debug.print("Error: Missing file argument\n\n", .{});
        std.debug.print("Usage: zig run {s}.zig -- <filename>\n", .{exe_name});
        return error.NoFileName;
    }

    const filename = try allocator.alloc(u8, args[1].len);
    errdefer allocator.free(filename);

    std.mem.copyForwards(u8, filename, args[1]);

    return filename;
}
