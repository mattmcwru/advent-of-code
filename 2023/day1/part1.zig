const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    var file = try std.fs.cwd().openFile("data.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var total_num: u32 = 0;

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        //std.debug.print("{s}\n", .{line});
        var merge_num = [2]u8{ ' ', ' ' };
        var first_num: u8 = 0;
        var last_num: u8 = 0;

        var i: usize = 0;
        while (i < line.len) : (i += 1) {
            if (line[i] >= '0' and line[i] <= '9') {
                first_num = line[i];
                break;
            }
        }
        try expect(first_num >= '0' and first_num <= '9');

        i = line.len;
        while (i > 0) {
            i -= 1;
            if (line[i] >= '0' and line[i] <= '9') {
                last_num = line[i];
                break;
            }
        }
        try expect(last_num >= '0' and last_num <= '9');

        merge_num[0] = first_num;
        merge_num[1] = last_num;

        var num_val = try std.fmt.parseInt(u32, &merge_num, 10);

        std.debug.print("{c}{c} {s} {}\n", .{ first_num, last_num, merge_num, num_val });

        total_num += num_val;
    }

    std.debug.print("Total: {}\n", .{total_num});
}
