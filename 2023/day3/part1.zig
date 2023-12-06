const std = @import("std");
const expect = std.testing.expect;

const Symbol = struct {
    symbol: u8,
    line_pos: usize,
    age: u8,
};

const Number = struct {
    line_start: usize,
    len: usize,
    value: u32,
    near_symbol: bool,
    age: u8,
};

const CharType = enum { symbol, number, other };

pub fn main() !void {
    var file = try std.fs.cwd().openFile("data.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    // Create Symbol and Number Lists
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var symbol_list = std.ArrayList(Symbol).init(gpa.allocator());
    defer symbol_list.deinit();

    var number_list = std.ArrayList(Number).init(gpa.allocator());
    defer number_list.deinit();

    var total_sum: u32 = 0;

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        std.debug.print("{s}", .{line});

        var prev_char: CharType = .other;

        for (line, 0..) |c, i| {
            var curr_char: CharType = .other;

            // Find symbol
            if (isSymbol(c)) {
                curr_char = .symbol;

                // Check if trailing character was a number
                var near_symbol = (prev_char == .number);

                // Check if symbol is near any numbers on previous line
                for (number_list.items, 0..) |item, ni| {
                    if (item.age == 1 and isNear(i, item.line_start, item.len)) {
                        number_list.items[ni].near_symbol = true;
                    }
                }

                // Update number if near symbol
                if (near_symbol) {
                    var n = number_list.pop();
                    n.near_symbol = true;
                    try number_list.append(n);
                }

                // Add new symbol to list
                try symbol_list.append(Symbol{ .symbol = c, .line_pos = i, .age = 0 });
            }

            // Find number
            if (isNumber(c)) {
                curr_char = .number;

                // Check if previous symbol was symbol
                var near_symbol = (prev_char == .symbol);

                // Check if number is near any symbols on previous line
                for (symbol_list.items) |item| {
                    if (item.age == 1 and isNear(i, item.line_pos, 1)) {
                        near_symbol = true;
                        break;
                    }
                }

                // Finish forming number
                if (prev_char == .number) {
                    // append number to list
                    var n = number_list.pop();
                    n.len += 1;
                    n.value = n.value * 10 + (c - '0');
                    n.near_symbol = n.near_symbol or near_symbol;
                    try number_list.append(n);
                } else {
                    // create new number in list
                    try number_list.append(Number{
                        .line_start = i,
                        .len = 1,
                        .value = c - '0',
                        .near_symbol = near_symbol,
                        .age = 0,
                    });
                }
            }

            prev_char = curr_char;
        }

        //std.debug.print("Symbols: {any}\n", .{symbol_list.items});
        //std.debug.print("Numbers: {any}\n", .{number_list.items});

        // pop old symbols
        var si = symbol_list.items.len;
        while (si > 0) {
            si -= 1;
            symbol_list.items[si].age += 1;
            if (symbol_list.items[si].age > 1)
                _ = symbol_list.swapRemove(si);
        }

        // compute finished numbers and pop old numbers
        var ni = number_list.items.len;
        while (ni > 0) {
            ni -= 1;

            // If the number is a valid part number then add to sum
            if (number_list.items[ni].near_symbol) {
                total_sum += number_list.items[ni].value;
                std.debug.print(" Added {}", .{number_list.items[ni].value});
            }

            // Increment the line age
            number_list.items[ni].age += 1;

            // Remove if not needed anymore
            if (number_list.items[ni].near_symbol or number_list.items[ni].age > 1)
                _ = number_list.swapRemove(ni);
        }

        std.debug.print("\n", .{});
    }

    std.debug.print("Total: {}\n", .{total_sum});
}

pub fn isNumber(c: u8) bool {
    return std.ascii.isDigit(c);
}

pub fn isSymbol(c: u8) bool {
    return if (c == '.' or std.ascii.isDigit(c)) false else true;
}

pub fn isNear(pos: usize, start: usize, len: usize) bool {
    return (pos >= (if (start > 0) (start - 1) else start) and pos <= (start + len));
}

test "test isNear" {
    try expect(isNear(0, 2, 3) == false);
    try expect(isNear(1, 2, 3) == true);
    try expect(isNear(2, 2, 3) == true);
    try expect(isNear(3, 2, 3) == true);
    try expect(isNear(4, 2, 3) == true);
    try expect(isNear(5, 2, 3) == true);
    try expect(isNear(6, 2, 3) == false);

    try expect(isNear(0, 0, 1) == true);
    try expect(isNear(1, 0, 1) == true);
    try expect(isNear(2, 0, 1) == false);
}
