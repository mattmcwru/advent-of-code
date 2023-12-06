const std = @import("std");
const expect = std.testing.expect;

const Symbol = struct {
    symbol: u8,
    value: [2]u32,
    gear_num: u8,
    line_pos: usize,
    age: u8,
    used: bool,
};

const Number = struct {
    line_start: usize,
    len: usize,
    value: u32,
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

                // Add new symbol to list
                try symbol_list.append(Symbol{
                    .symbol = c,
                    .value = .{ 0, 0 },
                    .line_pos = i,
                    .gear_num = 0,
                    .age = 0,
                    .used = false,
                });
            }

            // Find number
            if (isNumber(c)) {
                curr_char = .number;

                // Finish forming number
                if (prev_char == .number) {
                    // append number to list
                    var n = number_list.pop();
                    n.len += 1;
                    n.value = n.value * 10 + (c - '0');
                    try number_list.append(n);
                } else {
                    // create new number in list
                    try number_list.append(Number{
                        .line_start = i,
                        .len = 1,
                        .value = c - '0',
                        .age = 0,
                    });
                }
            }

            prev_char = curr_char;
        }

        //std.debug.print("Symbols: {any}\n", .{symbol_list.items});
        //std.debug.print("Numbers: {any}\n", .{number_list.items});

        // compute gears and pop old symbols
        var si = symbol_list.items.len;
        while (si > 0) {
            si -= 1;

            // Check if the symbol is near any numbers after the symbol
            for (number_list.items) |item| {
                if (symbol_list.items[si].age == 1 and item.age == 1) // Skip old data
                    continue;

                if (isNear(symbol_list.items[si].line_pos, item.line_start, item.len)) {
                    symbol_list.items[si].value[symbol_list.items[si].gear_num] = item.value;
                    symbol_list.items[si].gear_num += 1;
                }
            }

            try expect(symbol_list.items[si].gear_num <= 2);

            // If the number is a valid part number then add to sum
            if (symbol_list.items[si].gear_num == 2) {
                total_sum += symbol_list.items[si].value[0] * symbol_list.items[si].value[1];
                symbol_list.items[si].used = true; // Mark for deletion (may be problem if gear number over 2?)
                std.debug.print(" <{},{}>", .{ symbol_list.items[si].value[0], symbol_list.items[si].value[1] });
            }

            // Increment the line age
            symbol_list.items[si].age += 1;

            // Remove if not needed anymore
            if (symbol_list.items[si].used or symbol_list.items[si].age > 1)
                _ = symbol_list.swapRemove(si);
        }

        // pop old numbers
        var ni = number_list.items.len;
        while (ni > 0) {
            ni -= 1;

            // Increment the line age
            number_list.items[ni].age += 1;

            // Remove if not needed anymore
            if (number_list.items[ni].age > 1)
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
    return c == '*';
}

pub fn isNear(pos: usize, start: usize, len: usize) bool {
    return (pos >= (if (start > 0) (start - 1) else start) and pos <= (start + len));
}
