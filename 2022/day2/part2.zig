const std = @import("std");
const expect = std.testing.expect;

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

    var total_score: u32 = 0;

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        try stdout.print("{s} ", .{line});

        try expect(line.len == 3);

        const opponent_hand = try detectHand(line[0]);
        const my_hand = try detectPlay(line[2], opponent_hand);
        const hand_score = scoreHand(my_hand, opponent_hand);

        const my_hand_char: u8 = switch (my_hand) {
            .Rock => 'A',
            .Paper => 'B',
            .Scissors => 'C',
        };

        try stdout.print("{c} {any}\n", .{ my_hand_char, hand_score });

        total_score += hand_score;
    }

    try stdout.print("\nTotal: {}\n", .{total_score});
}

const Hands = enum { Rock, Paper, Scissors };

fn detectHand(h: u8) error{BadInput}!Hands {
    return switch (h) {
        'A' => .Rock,
        'B' => .Paper,
        'C' => .Scissors,
        else => error.BadInput,
    };
}

fn detectPlay(play: u8, their: Hands) error{BadInput}!Hands {
    return switch (play) {
        'X' => switch (their) { // Lose
            .Rock => .Scissors,
            .Paper => .Rock,
            .Scissors => .Paper,
        },
        'Y' => their, // Draw
        'Z' => switch (their) { // Win
            .Rock => .Paper,
            .Paper => .Scissors,
            .Scissors => .Rock,
        },
        else => error.BadInput,
    };
}

const Scores = struct {
    Win: u8 = 6,
    Draw: u8 = 3,
    Lose: u8 = 0,
    RockBonus: u8 = 1,
    PaperBonus: u8 = 2,
    ScissorsBonus: u8 = 3,
};

fn scoreHand(mine: Hands, their: Hands) u8 {
    const s = Scores{};
    return switch (@as(Hands, mine)) {
        .Rock => s.RockBonus + switch (@as(Hands, their)) {
            .Rock => s.Draw,
            .Paper => s.Lose,
            .Scissors => s.Win,
        },
        .Paper => s.PaperBonus + switch (@as(Hands, their)) {
            .Rock => s.Win,
            .Paper => s.Draw,
            .Scissors => s.Lose,
        },
        .Scissors => s.ScissorsBonus + switch (@as(Hands, their)) {
            .Rock => s.Lose,
            .Paper => s.Win,
            .Scissors => s.Draw,
        },
    };
}

test "Hand Scoring" {
    const s = Scores{};
    try expect(scoreHand(.Rock, .Rock) == s.Draw + s.RockBonus);
    try expect(scoreHand(.Rock, .Paper) == s.Lose + s.RockBonus);
    try expect(scoreHand(.Rock, .Scissors) == s.Win + s.RockBonus);

    try expect(scoreHand(.Paper, .Rock) == s.Win + s.PaperBonus);
    try expect(scoreHand(.Paper, .Paper) == s.Draw + s.PaperBonus);
    try expect(scoreHand(.Paper, .Scissors) == s.Lose + s.PaperBonus);

    try expect(scoreHand(.Scissors, .Rock) == s.Lose + s.ScissorsBonus);
    try expect(scoreHand(.Scissors, .Paper) == s.Win + s.ScissorsBonus);
    try expect(scoreHand(.Scissors, .Scissors) == s.Draw + s.ScissorsBonus);
}
