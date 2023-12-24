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

    var brick_list = std.ArrayList(Brick).init(allocator);
    defer {
        for (brick_list.items) |brick| brick.deinit();
        brick_list.deinit();
    }

    var id: usize = 1;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var toks = std.mem.tokenizeAny(u8, line, ",~");

        const x1: usize = if (toks.next()) |x| try std.fmt.parseInt(usize, x, 10) else return error.MissingBrickCoordinate;
        const y1: usize = if (toks.next()) |x| try std.fmt.parseInt(usize, x, 10) else return error.MissingBrickCoordinate;
        const z1: usize = if (toks.next()) |x| try std.fmt.parseInt(usize, x, 10) else return error.MissingBrickCoordinate;

        const x2: usize = if (toks.next()) |x| try std.fmt.parseInt(usize, x, 10) else return error.MissingBrickCoordinate;
        const y2: usize = if (toks.next()) |x| try std.fmt.parseInt(usize, x, 10) else return error.MissingBrickCoordinate;
        const z2: usize = if (toks.next()) |x| try std.fmt.parseInt(usize, x, 10) else return error.MissingBrickCoordinate;

        try brick_list.append(Brick.init(allocator, id, x1, y1, z1, x2, y2, z2));
        id += 1;
    }

    // Print the brick list
    for (brick_list.items) |brick| {
        print("{} {} {} - {} {} {}\n", .{ brick.left.x, brick.left.y, brick.left.z, brick.right.x, brick.right.y, brick.right.z });
    }

    // Sort the bricks in order of height
    var bricks = try brick_list.toOwnedSlice();
    defer {
        for (bricks) |brick| brick.deinit();
        allocator.free(bricks);
    }
    std.mem.sort(Brick, bricks, {}, Brick.lessThanZ);

    // Print sorted brick list
    print("\nSorted\n", .{});
    for (bricks) |brick| {
        print("{:4}: {} {} {} - {} {} {}\n", .{ brick.id, brick.left.x, brick.left.y, brick.left.z, brick.right.x, brick.right.y, brick.right.z });
    }

    // Make floating bricks fall
    for (0..bricks.len) |i| {
        var tallest_found: usize = 0;
        var tallest_index: usize = 0;

        var j = i;
        while (j > 0) { // Find tallest brick under this one
            j -= 1;
            if (bricks[i].isOver(bricks[j])) {
                var height = @max(bricks[j].left.z, bricks[j].right.z);
                if (height > tallest_found) {
                    tallest_found = height;
                    tallest_index = j;
                }
            }
        }

        if (tallest_found > 0) { // Brick falls to next lower brick
            var gap = bricks[tallest_index].gapZ(bricks[i]);
            try expect(gap > 0);
            if (gap > 1) {
                bricks[i].left.z -= gap - 1;
                bricks[i].right.z -= gap - 1;
            }
        } else { // Brick falls to ground
            const gap = @min(bricks[i].left.z, bricks[i].right.z);
            try expect(gap > 0);
            if (gap > 1) {
                bricks[i].left.z -= gap - 1;
                bricks[i].right.z -= gap - 1;
            }
        }
    }

    // Re-sort list
    //std.mem.sort(Brick, bricks, {}, Brick.lessThanZ);

    // Determine how many bricks are supporting each brick
    for (0..bricks.len) |i| {
        var j = i;
        while (j > 0) {
            j -= 1;
            if (bricks[j].isOver(bricks[i])) {
                var gap = bricks[j].gapZ(bricks[i]);
                if (gap == 0) print("Gap 0: {} {any} {any} : {} {any} {any}\n", .{ bricks[i].id, bricks[i].left, bricks[i].right, bricks[j].id, bricks[j].left, bricks[j].right });
                try expect(gap > 0);
                if (gap == 1) {
                    bricks[i].supported_by += 1;
                    try bricks[j].supporting_list.append(&bricks[i]);
                }
            }
        }
    }

    //Print grounded brick list
    print("\nGrounded\n", .{});
    for (bricks) |brick| {
        print("{:4}: {} {} {:3} - {} {} {:3} | {} {} {any:5} | ", .{
            brick.id,
            brick.left.x,
            brick.left.y,
            brick.left.z,
            brick.right.x,
            brick.right.y,
            brick.right.z,
            brick.supported_by,
            brick.supporting_list.items.len,
            brick.isDisintegrable(),
        });

        for (brick.supporting_list.items) |b| {
            print(" {} {} {:3} - {} {} {:3} ", .{
                b.left.x,
                b.left.y,
                b.left.z,
                b.right.x,
                b.right.y,
                b.right.z,
            });
        }
        print("\n", .{});
    }

    // Determine how many bricks can be disintegrated
    var total_disintegrable: usize = 0;
    for (bricks) |brick| {
        if (brick.isDisintegrable()) total_disintegrable += 1;
    }
    print("\nTotal disintegrable: {}\n", .{total_disintegrable});
}

const Brick = struct {
    id: usize,
    left: Coord,
    right: Coord,
    supported_by: usize,
    supporting_list: std.ArrayList(*Brick),
    allocator: std.mem.Allocator,

    const Coord = struct {
        x: usize,
        y: usize,
        z: usize,
    };

    pub fn init(allocator: std.mem.Allocator, id: usize, x1: usize, y1: usize, z1: usize, x2: usize, y2: usize, z2: usize) Brick {
        return .{
            .id = id,
            .left = .{ .x = x1, .y = y1, .z = z1 },
            .right = .{ .x = x2, .y = y2, .z = z2 },
            .supported_by = 0,
            .supporting_list = std.ArrayList(*Brick).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Brick) void {
        self.supporting_list.deinit();
    }

    pub fn isOver(a: Brick, b: Brick) bool {
        return (a.left.x <= b.right.x) and (a.right.x >= b.left.x) and (a.left.y <= b.right.y) and (a.right.y >= b.left.y);
    }

    pub fn isAbove(a: Brick, b: Brick) bool {
        return isOver(a, b) and @max(a.left.z, a.right.z) > @min(b.left.z, b.right.z);
    }

    pub fn str(self: Brick, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{},{},{}-{},{},{}", .{ self.left.x, self.left.y, self.left.z, self.right.x, self.right.y, self.right.z });
    }

    pub fn lessThanZ(_: void, a: Brick, b: Brick) bool {
        return @min(a.left.z, a.right.z) < @min(b.left.z, b.right.z) or
            (@min(a.left.z, a.right.z) == @min(b.left.z, b.right.z) and @max(a.left.z, a.right.z) < @max(b.left.z, b.right.z));
    }

    pub fn isTouching(a: Brick, b: Brick) bool {
        return isOver(a, b) and diff(@max(a.left.z, a.right.z), @min(b.left.z, b.right.z)) == 1;
    }

    pub fn onGround(self: Brick) bool {
        return @min(self.left.z, self.right.z) == 1;
    }

    pub fn gapZ(a: Brick, b: Brick) usize {
        return diff(@max(a.left.z, a.right.z), @min(b.left.z, b.right.z));
    }

    pub fn isDisintegrable(self: Brick) bool {
        for (self.supporting_list.items) |brick| {
            if (brick.*.supported_by < 2)
                return false;
        }
        return true;
    }
};

pub fn diff(a: anytype, b: anytype) @TypeOf(a) {
    return if (a > b) a - b else b - a;
}

test "Brick isOver" {
    const allocator = std.testing.allocator;

    const a = Brick.init(allocator, 0, 1, 0, 1, 1, 2, 1);
    const b = Brick.init(allocator, 1, 0, 0, 2, 2, 0, 2);

    print("\n{any}\n", .{(a.left.x <= b.right.x)});
    print("{any}\n", .{(a.right.x >= b.left.x)});
    print("{any}\n", .{(a.left.y <= b.right.y)});
    print("{any}\n", .{(a.right.y >= b.left.y)});
    print("{any}\n", .{@max(a.left.z, a.right.z) < @min(b.left.z, b.right.z)});

    const a_over_b = a.isOver(b);
    const b_over_a = b.isOver(a);
    const a_above_b = a.isAbove(b);
    const b_above_a = b.isAbove(a);

    print("a over b = {any}\n", .{a_over_b});
    print("b over a = {any}\n", .{b_over_a});
    print("a above b = {any}\n", .{a_above_b});
    print("b above a = {any}\n", .{b_above_a});

    try expect(a_over_b == true);
    try expect(b_over_a == true);
    try expect(a_above_b == false);
    try expect(b_above_a == true);
}

test "Brick lessThanZ" {
    const allocator = std.testing.allocator;

    const a = Brick.init(allocator, 0, 1, 0, 1, 1, 2, 1);
    const b = Brick.init(allocator, 1, 0, 0, 2, 2, 0, 2);
    const c = Brick.init(allocator, 2, 0, 0, 1, 2, 0, 3);

    const a_lt_b = Brick.lessThanZ({}, a, b);
    const a_lt_c = Brick.lessThanZ({}, a, c);
    const b_lt_c = Brick.lessThanZ({}, b, c);
    const c_lt_b = Brick.lessThanZ({}, c, b);

    print("\na lt b = {any}\n", .{a_lt_b});
    print("a lt c = {any}\n", .{a_lt_c});
    print("b lt c = {any}\n", .{b_lt_c});
    print("c lt b = {any}\n", .{c_lt_b});

    try expect(a_lt_b == true);
    try expect(a_lt_c == true);
    try expect(b_lt_c == false);
    try expect(c_lt_b == true);
}

test "Brick isTouching" {
    const allocator = std.testing.allocator;

    const a = Brick.init(allocator, 0, 1, 0, 1, 1, 2, 1);
    const b = Brick.init(allocator, 1, 0, 0, 2, 2, 0, 2);
    const c = Brick.init(allocator, 2, 0, 0, 3, 2, 0, 3);
    const d = Brick.init(allocator, 3, 0, 1, 2, 2, 1, 2);

    const a_touch_b = Brick.isTouching(a, b);
    const a_touch_c = Brick.isTouching(a, c);
    const b_touch_c = Brick.isTouching(b, c);
    const b_touch_d = Brick.isTouching(b, d);

    print("\na touch b = {any}\n", .{a_touch_b});
    print("a touch c = {any}\n", .{a_touch_c});
    print("b touch c = {any}\n", .{b_touch_c});
    print("b touch d = {any}\n", .{b_touch_d});

    try expect(a_touch_b == true);
    try expect(a_touch_c == false);
    try expect(b_touch_c == true);
    try expect(b_touch_d == false);
}

test "Brick gapZ" {
    const allocator = std.testing.allocator;

    const a = Brick.init(allocator, 0, 9, 1, 3, 9, 1, 6);
    const b = Brick.init(allocator, 1, 9, 0, 8, 9, 2, 8);

    const a_b_gap = Brick.gapZ(a, b);

    print("\na b gap = {any}\n", .{a_b_gap});
}
