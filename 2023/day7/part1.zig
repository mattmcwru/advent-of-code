const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;

const TreeData = struct {
    hand: Hand,
    score: Hand.HandScore,
};

const SortTree = struct {
    root: ?*TreeNode = null,
    allocator: std.mem.Allocator = undefined,

    pub const TreeNode = struct {
        left: ?*TreeNode = null,
        right: ?*TreeNode = null,
        data: TreeData,

        pub fn init(data: TreeData) TreeNode {
            return TreeNode{ .data = data };
        }

        pub fn deinit(self: *TreeNode, allocator: std.mem.Allocator) void {
            if (self.left) |n| {
                print(" deinit left\n", .{});
                n.deinit(allocator);
                allocator.destroy(n);
            }
            if (self.right) |n| {
                print(" deinit right\n", .{});
                n.deinit(allocator);
                allocator.destroy(n);
            }
        }

        pub fn addNode(self: *TreeNode, data: TreeData, allocator: std.mem.Allocator) !void {
            if (@intFromEnum(self.data.score) < @intFromEnum(data.score)) {
                if (self.left) |n| {
                    print(" Add node to left\n", .{});
                    try n.addNode(data, allocator);
                } else {
                    print("  Create left node\n", .{});
                    self.left = try self.createNode(data, allocator);
                }
            } else {
                if (self.right) |n| {
                    print(" Add node to right\n", .{});
                    try n.addNode(data, allocator);
                } else {
                    print("  Create right node\n", .{});
                    self.right = try self.createNode(data, allocator);
                }
            }
        }

        pub fn createNode(self: TreeNode, data: TreeData, allocator: std.mem.Allocator) !*TreeNode {
            _ = self;
            var node = try allocator.create(TreeNode);
            node.* = TreeNode.init(data);
            return node;
        }
    };

    pub fn init(gpa: std.mem.Allocator) SortTree {
        return SortTree{ .allocator = gpa };
    }

    pub fn deinit(self: SortTree) void {
        if (self.root) |r| {
            print("deinit root\n", .{});
            r.deinit(self.allocator);
            self.allocator.destroy(r);
        }
    }

    pub fn addNode(self: *SortTree, data: TreeData) !void {
        if (self.root) |r| {
            print("Add node to root\n", .{});
            try r.addNode(data, self.allocator);
        } else {
            print("Create root node\n", .{});
            var node = try self.allocator.create(TreeNode);
            node.* = TreeNode.init(data);
            self.root = node;
        }
    }
};

test "Sort Tree" {
    print("\n", .{});

    var tree = SortTree.init(std.testing.allocator);
    defer tree.deinit();

    //print("{any}\n", .{tree});

    try tree.addNode(.{ .hand = .{ .cards = .{.card_3} ** 5, .bet = 0 }, .score = .FullHouse });
    try tree.addNode(.{ .hand = .{ .cards = .{.card_2} ** 5, .bet = 0 }, .score = .FiveOfKind });
    try tree.addNode(.{ .hand = .{ .cards = .{.card_3} ** 5, .bet = 0 }, .score = .OnePair });
    try tree.addNode(.{ .hand = .{ .cards = .{.card_3} ** 5, .bet = 0 }, .score = .OnePair });
    try tree.addNode(.{ .hand = .{ .cards = .{.card_3} ** 5, .bet = 0 }, .score = .OnePair });
}

const Hand = struct {
    cards: [5]Cards,
    bet: u32,

    pub const HandScore = enum(u3) {
        FiveOfKind = 7,
        FourOfKind = 6,
        FullHouse = 5,
        ThreeOfKind = 4,
        TwoPair = 3,
        OnePair = 2,
        HighCard = 1,
    };

    pub fn score(self: Hand) HandScore {
        const Match = struct { count: u4, card: Cards };

        var matchs: [2]Match = undefined;

        matchs[0] = .{ .count = 0, .card = .nocard };
        matchs[1] = .{ .count = 0, .card = .nocard };

        for (0..5) |i| {
            for (i + 1..5) |j| {
                if (self.cards[i] == self.cards[j]) {
                    if (matchs[0].card == .nocard or matchs[0].card == self.cards[i]) {
                        matchs[0].card = self.cards[i];
                        matchs[0].count += 1;
                    } else if (matchs[1].card == .nocard or matchs[1].card == self.cards[i]) {
                        matchs[1].card = self.cards[i];
                        matchs[1].count += 1;
                    }

                    break;
                }
            }
        }

        //std.debug.print("Match 1 = [{},{s}]  Match 2 = [{},{s}]\n", .{ matchs[0].count, matchs[0].card.name(), matchs[1].count, matchs[1].card.name() });
        if (matchs[0].card == .nocard) return .HighCard;

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

    pub fn print(self: Hand) void {
        const c = self.cards;
        std.debug.print("{s} {s} {s} {s} {s}\n", .{ c[0].name(), c[1].name(), c[2].name(), c[3].name(), c[4].name() });
    }
};

const Cards = enum(u4) {
    card_A = 14,
    card_K = 13,
    card_Q = 12,
    card_J = 11,
    card_T = 10,
    card_9 = 9,
    card_8 = 8,
    card_7 = 7,
    card_6 = 6,
    card_5 = 5,
    card_4 = 4,
    card_3 = 3,
    card_2 = 2,
    nocard = 0,

    pub fn getcard(c: u8) Cards {
        return switch (c) {
            'A' => .card_A,
            'K' => .card_K,
            'Q' => .card_Q,
            'J' => .card_J,
            'T' => .card_T,
            '9' => .card_9,
            '8' => .card_8,
            '7' => .card_7,
            '6' => .card_6,
            '5' => .card_5,
            '4' => .card_4,
            '3' => .card_3,
            '2' => .card_2,
            else => .nocard,
        };
    }

    pub fn max(self: Cards, c: Cards) Cards {
        return if (@intFromEnum(self) > @intFromEnum(c)) self else c;
    }

    pub fn gt(self: Cards, c: Cards) Cards {
        return if (@intFromEnum(self) > @intFromEnum(c)) self else c;
    }

    pub fn name(self: Cards) []const u8 {
        return @tagName(self);
    }
};

// libs/ points to ../../libs/ via a symlink
// This is wrong but not sure how to add a module path when using zig run directly.
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs;

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    const filename = getFileNameFromArgs(allocator) catch return;
    defer allocator.free(filename);

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        print("{s}\n", .{line});
        var split_line = std.mem.splitScalar(u8, line, ' ');

        var hand = Hand{ .cards = .{.nocard} ** 5, .bet = 0 };

        // Parse hand
        if (split_line.next()) |sline| {
            try expect(hand.cards.len == sline.len);
            for (&hand.cards, sline) |*h, s| {
                h.* = Cards.getcard(s);
            }
        }

        // Parse bet
        if (split_line.next()) |sline| {
            hand.bet = try std.fmt.parseInt(u32, sline, 10);
        }

        var score = hand.score();
        print("{s}\n", .{@tagName(score)});

        // Add hand to tree

    }
}
