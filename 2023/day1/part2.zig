const std = @import("std");
const expect = std.testing.expect;

pub fn isNumberWordOrDigit(line: []const u8) ?u8 {
    const number_words = [_][]const u8{ "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" };
    return switch (line[0]) {
        '0'...'9' => line[0] - '0',
        'z' => if (std.mem.startsWith(u8, line, number_words[0])) 0 else null,
        'o' => if (std.mem.startsWith(u8, line, number_words[1])) 1 else null,
        't' => if (std.mem.startsWith(u8, line, number_words[2])) 2 else if (std.mem.startsWith(u8, line, number_words[3])) 3 else null,
        'f' => if (std.mem.startsWith(u8, line, number_words[4])) 4 else if (std.mem.startsWith(u8, line, number_words[5])) 5 else null,
        's' => if (std.mem.startsWith(u8, line, number_words[6])) 6 else if (std.mem.startsWith(u8, line, number_words[7])) 7 else null,
        'e' => if (std.mem.startsWith(u8, line, number_words[8])) 8 else null,
        'n' => if (std.mem.startsWith(u8, line, number_words[9])) 9 else null,
        else => null,
    };
}

pub fn main() !void {
    var file = try std.fs.cwd().openFile("data.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var total_num: usize = 0;

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var first_digit: ?u8 = null;
        var last_digit: ?u8 = null;
        var i: usize = 0;

        // Find first digit
        i = 0;
        while (first_digit == null and i < line.len) : (i += 1) {
            first_digit = isNumberWordOrDigit(line[i..]);
        }

        // Find last digit
        i = line.len;
        while (last_digit == null and i > 0) {
            i -= 1;
            last_digit = isNumberWordOrDigit(line[i..]);
        }

        try expect(first_digit != null and last_digit != null);

        const number_value = first_digit.? * 10 + last_digit.?;

        std.debug.print("{?} {?} {} {s}\n", .{ first_digit, last_digit, number_value, line });

        total_num += number_value;
    }

    std.debug.print("Total: {}\n", .{total_num});
}
