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

    var total_points: u32 = 0;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var winners_list = std.ArrayList(u8).init(gpa.allocator());
    defer winners_list.deinit();
    var your_num_list = std.ArrayList(u8).init(gpa.allocator());
    defer your_num_list.deinit();

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        //try stdout.print("{s}\n", .{line});

        // Get the card id
        var card_tok = std.mem.tokenizeScalar(u8, line, ':');
        const card_id = card_tok.next();
        var card_id_num = try std.fmt.parseInt(u32, std.mem.trim(u8, card_id.?[5..], " "), 10);
        try stdout.print("Card {d:3} ", .{card_id_num});

        // Split the data into groups
        var group_tok = std.mem.tokenizeScalar(u8, card_tok.rest(), '|');

        const winning_numbers = group_tok.next() orelse "";
        const your_numbers = group_tok.next() orelse "";

        try stdout.print("{s} | {s} ", .{ winning_numbers, your_numbers });

        // Parse the numbers
        var winners_tok = std.mem.tokenizeScalar(u8, winning_numbers, ' ');
        var your_num_tok = std.mem.tokenizeScalar(u8, your_numbers, ' ');

        // Convert input strings to number arrays
        winners_list.clearRetainingCapacity();
        while (winners_tok.next()) |win_num| {
            try winners_list.append(try std.fmt.parseInt(u8, win_num, 10));
        }

        your_num_list.clearRetainingCapacity();
        while (your_num_tok.next()) |your_num| {
            try your_num_list.append(try std.fmt.parseInt(u8, your_num, 10));
        }

        var points: u32 = 0;
        var found_first: bool = false;

        for (winners_list.items) |win_num| {
            for (your_num_list.items) |your_num| {
                if (your_num == win_num) {
                    try stdout.print("{s}{}", .{ if (!found_first) "found (" else ", ", win_num });
                    points = if (points == 0) 1 else points * 2;
                    found_first = true;
                }
            }
        }
        const end_b: []const u8 = if (found_first) ") " else " ";
        try stdout.print("{s}Points {}\n", .{ end_b, points });

        total_points += points;
    }

    try stdout.print("Total Points {}\n", .{total_points});
}
