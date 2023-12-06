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

    var total_cards: u32 = 0;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var winners_list = std.ArrayList(u8).init(gpa.allocator());
    defer winners_list.deinit();
    var your_num_list = std.ArrayList(u8).init(gpa.allocator());
    defer your_num_list.deinit();

    var card_stack = std.ArrayList(u32).init(gpa.allocator());
    defer card_stack.deinit();

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

        var num_of_winners: u8 = 0;

        // Check for winning cards
        for (winners_list.items) |win_num| {
            for (your_num_list.items) |your_num| {
                if (your_num == win_num) {
                    try stdout.print("{s}{}", .{ if (num_of_winners == 0) "found (" else ", ", win_num });
                    num_of_winners += 1;
                }
            }
        }

        // Get the copy count and remove the current card from stack
        const card_copies = 1 + if (card_stack.items.len == 0) 0 else card_stack.orderedRemove(0);

        for (0..num_of_winners) |i| {
            if (i < card_stack.items.len) {
                card_stack.items[i] += card_copies;
            } else {
                try card_stack.append(card_copies);
            }
        }

        const end_b: []const u8 = if (num_of_winners > 0) ") " else " ";
        try stdout.print("{s}Cards {} Winners {}\n", .{ end_b, card_copies, num_of_winners });

        total_cards += card_copies;
    }

    try stdout.print("Total Cards {}\n", .{total_cards});
}
