const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const gpa_status = gpa.deinit();
        if (gpa_status == .leak) expect(false) catch @panic("GPA Leaked Memory");
    }

    const filename = getFileNameFromArgs(allocator) catch return;
    defer allocator.free(filename);

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var hand_list = std.MultiArrayList(Hand){};
    defer hand_list.deinit(allocator);

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        print("{s} ", .{line});
        var split_line = std.mem.splitScalar(u8, line, ' ');

        const hand = if (split_line.next()) |s| s else undefined;
        const bet = if (split_line.next()) |s| try std.fmt.parseInt(u32, s, 10) else undefined;

        try expect(hand.len == 5);
        try expect(bet > 0);

        var theHand = Hand.init(hand, bet);
        print("{s}\n", .{theHand.hand_type.name()});

        // Add hand to tree
        try hand_list.append(allocator, theHand);
    }

    // Sort the list
    hand_list.sort(Hand.SortCtx{ .slice = hand_list.slice() });

    print("list size = {}\n", .{hand_list.len});

    var total_winnings: usize = 0;

    for (hand_list.items(.cards), hand_list.items(.hand_type), hand_list.items(.bet), 1..) |cs, ht, b, i| {
        print("Rank {} ", .{i});
        for (cs) |c| {
            print("{c}", .{c.name()});
        }
        print(" {s}\n", .{ht.name()});

        total_winnings += i * b;
    }

    print("Total Winnings: {}\n", .{total_winnings});
}

const Hand = struct {
    cards: Cards,
    bet: u32,
    hand_type: HandType,

    const Cards = [5]Card;

    const Card = enum(u4) {
        _A = 14,
        _K = 13,
        _Q = 12,
        //_J = 11,
        _T = 10,
        _9 = 9,
        _8 = 8,
        _7 = 7,
        _6 = 6,
        _5 = 5,
        _4 = 4,
        _3 = 3,
        _2 = 2,
        _J = 1, // Jack == Joker
        nocard = 0,

        pub fn isLessThan(a: Card, b: Card) bool {
            return @intFromEnum(b) < @intFromEnum(a);
        }

        pub fn name(self: Card) u8 {
            const n = " J23456789TJQKA";
            return n[@intFromEnum(self)];
        }
    };

    const HandType = enum(u3) {
        FiveOfKind = 7,
        FourOfKind = 6,
        FullHouse = 5,
        ThreeOfKind = 4,
        TwoPair = 3,
        OnePair = 2,
        HighCard = 1,

        pub fn name(self: HandType) []const u8 {
            return switch (self) {
                .FiveOfKind => "Five Of Kind",
                .FourOfKind => "Four Of Kind",
                .FullHouse => "Full House",
                .ThreeOfKind => "Three Of Kind",
                .TwoPair => "Two Pair",
                .OnePair => "One Pair",
                .HighCard => "High Card",
            };
        }

        pub fn isLessThan(a: HandType, b: HandType) bool {
            return @intFromEnum(b) < @intFromEnum(a);
        }
    };

    pub fn init(hand: []const u8, bet: u32) Hand {
        var cards: Cards = undefined;
        for (&cards, hand) |*c, h| {
            c.* = Hand.getCard(h);
        }
        return .{
            .cards = cards,
            .bet = bet,
            .hand_type = Hand.getHandType(cards),
        };
    }

    pub fn getCard(c: u8) Card {
        return switch (c) {
            'A' => ._A,
            'K' => ._K,
            'Q' => ._Q,
            'J' => ._J,
            'T' => ._T,
            '9' => ._9,
            '8' => ._8,
            '7' => ._7,
            '6' => ._6,
            '5' => ._5,
            '4' => ._4,
            '3' => ._3,
            '2' => ._2,
            else => .nocard,
        };
    }

    pub fn getHandType(cards: Cards) HandType {
        const Match = struct { count: u4, card: Card };
        var matchs: [3]Match = undefined;

        matchs[0] = .{ .count = 0, .card = .nocard };
        matchs[1] = .{ .count = 0, .card = .nocard };
        matchs[2] = .{ .count = 0, .card = ._J };

        for (0..5) |i| {
            if (cards[i] == ._J) {
                matchs[2].count += 1;
                continue;
            }

            for (i + 1..5) |j| {
                if (cards[i] == cards[j]) {
                    if (matchs[0].card == .nocard or matchs[0].card == cards[i]) {
                        matchs[0].card = cards[i];
                        matchs[0].count += 1;
                    } else if (matchs[1].card == .nocard or matchs[1].card == cards[i]) {
                        matchs[1].card = cards[i];
                        matchs[1].count += 1;
                    }
                    break;
                }
            }
        }

        // Add jokers to match with higher count (default to match[0])
        if (matchs[0].count >= matchs[1].count) {
            matchs[0].count += matchs[2].count;
        } else {
            matchs[1].count += matchs[2].count;
        }

        if (matchs[0].card == .nocard) {
            if (matchs[2].count > 0) {
                matchs[0].card = ._J;
                if (matchs[2].count == 5)
                    matchs[0].count -= 1;
            } else {
                return .HighCard;
            }
        }

        if (matchs[1].card == .nocard) {
            return switch (matchs[0].count) {
                4 => .FiveOfKind,
                3 => .FourOfKind,
                2 => .ThreeOfKind,
                1 => .OnePair,
                0 => .HighCard,
                else => undefined,
            };
        } else {
            return switch (matchs[0].count) {
                2 => if (matchs[1].count == 1) .FullHouse else undefined,
                1 => switch (matchs[1].count) {
                    2 => .FullHouse,
                    1 => .TwoPair,
                    else => undefined,
                },
                else => undefined,
            };
        }

        return undefined;
    }

    pub fn isLessThan(a: Hand, b: Hand) bool {
        if (a.hand_type != b.hand_type)
            return a.hand_type.isLessThan(b.hand_type);

        for (a.cards, b.cards) |ac, bc| {
            if (ac == bc) continue;
            return ac.isLessThan(bc);
        }
        return false; // hands are equal
    }

    const SortCtx = struct {
        slice: std.MultiArrayList(Hand).Slice,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.slice.get(b).isLessThan(ctx.slice.get(a));
        }
    };
};

test "getHandType" {
    const test_hands = [_][]const u8{ "J3854", "JJ235", "JJJ34", "JJJJ3", "JJJJJ" };

    for (test_hands) |th| {
        var hand = Hand.init(th, 0);

        for (hand.cards) |c| {
            print("{c}", .{c.name()});
        }
        print(" {s}\n", .{hand.hand_type.name()});
    }
}
