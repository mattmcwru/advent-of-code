const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() == .leak) expect(false) catch @panic("GPA Leaked Memory");

    const filename = getFileNameFromArgs(allocator) catch return;
    defer allocator.free(filename);

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var total_sum: usize = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, ',')) |sequence| {
        const hash = run_hash(sequence);
        total_sum += hash;
        print("{s} => {}\n", .{ sequence, hash });
    }

    print("\nTotal Sum is {}\n", .{total_sum});
}

pub fn run_hash(string: []const u8) u8 {
    var sum: u16 = 0;
    for (string) |c| {
        sum = @mod((sum + c) * 17, 256);
    }
    return std.mem.toBytes(sum)[0];
}

test "run_hash" {
    const hval = run_hash("HASH");
    try expect(hval == 52);
    print("{}\n", .{hval});
}
