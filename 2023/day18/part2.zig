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

    var dig_plan = DigPlan.init(allocator);
    defer dig_plan.deinit();

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var split_line = std.mem.splitBackwardsScalar(u8, line, ' ');
        var op: DigOp = undefined;

        // Get the instruction
        if (split_line.next()) |sl| {
            const inst = std.mem.trim(u8, sl, "(#)");
            try expect(inst.len == 6);

            op.dist = try std.fmt.parseInt(usize, inst[0..5], 16);
            op.dir = switch (inst[5]) {
                '0' => .right,
                '1' => .down,
                '2' => .left,
                '3' => .up,
                else => return error.BadSymbol,
            };
        } else return error.MissingInput;

        try dig_plan.append(op);
    }

    // Find the vertices of the shape
    var vertex_list = std.ArrayList(Vertex).init(allocator);
    defer vertex_list.deinit();
    var at = Vertex{ .x = 0, .y = 0 };
    var dig_dist: usize = 0;
    for (dig_plan.items) |op| {
        dig_dist += op.dist;
        const pt = switch (op.dir) {
            .up => Vertex{ .x = at.x, .y = at.y + @as(isize, @intCast(op.dist)) },
            .down => Vertex{ .x = at.x, .y = at.y - @as(isize, @intCast(op.dist)) },
            .left => Vertex{ .x = at.x - @as(isize, @intCast(op.dist)), .y = at.y },
            .right => Vertex{ .x = at.x + @as(isize, @intCast(op.dist)), .y = at.y },
        };
        try vertex_list.append(pt);
        at.x = pt.x;
        at.y = pt.y;
    }

    // Find area of vertex list
    var area = try areaVertexList(vertex_list.items);

    for (dig_plan.items, 0..) |op, i| {
        print("{s:5} {} ({},{})\n", .{ @tagName(op.dir), op.dist, vertex_list.items[i].x, vertex_list.items[i].y });
    }

    var turn_count = countTurns(vertex_list.items);
    print("In: {} Out: {}\n", .{ turn_count.in, turn_count.out });

    print("Area: {}  Length: {}\n", .{ area, dig_dist });
}

const VertexList = std.ArrayList(Vertex);
const Vertex = struct {
    x: isize,
    y: isize,
};

const Direction = enum { up, down, left, right };
const RGBCode = struct {
    red: u8,
    green: u8,
    blue: u8,
};

const DigPlan = std.ArrayList(DigOp);

const DigOp = struct {
    dir: Direction,
    dist: usize,
};

// https://www.mathopenref.com/coordpolygonarea2.html
pub fn areaVertexList(list: []const Vertex) !isize {
    const turns = countTurns(list);
    if (turns.in < turns.out)
        return error.ListWrongDirection;

    var area: isize = 0;
    var j = list.len - 1;
    for (0..list.len) |i| {
        area += (list[j].x + list[i].x) * (list[j].y - list[i].y); // Segment area
        area += segLength(list[j], list[i]);
        j = i;
        print("Area {}: {}\n", .{ i, area });
    }
    area = @divTrunc(area, 2) + 1;

    // Not sure why @abs() does not work (zig 0.11.0)
    return if (area < 0) -area else area;
}

pub fn segLength(a: Vertex, b: Vertex) isize {
    const x_diff = a.x - b.x;
    const y_diff = a.y - b.y;
    return if (a.x == b.x)
        std.math.absInt(y_diff) catch 0
    else if (a.y == b.y)
        std.math.absInt(x_diff) catch 0
    else
        @panic("fix this");
    //  error.FixThis; //@panic("fix this");
    //std.math.sqrt(x_diff * x_diff + y_diff * y_diff);
}

pub fn countTurns(list: []const Vertex) struct { in: usize, out: usize } {
    var in: usize = 0;
    var out: usize = 0;

    var j = list.len - 1;
    var k: usize = 1;

    for (0..list.len) |i| {
        k = @mod(i + 1, list.len);
        //print("Turns {},{},{}: ", .{ j, i, k });

        if (list[j].x * (list[k].y - list[i].y) +
            list[i].x * (list[j].y - list[k].y) +
            list[k].x * (list[i].y - list[j].y) < 0) out += 1 else in += 1;

        j = i;

        //print("{} {}\n", .{ out, in });
    }
    return .{ .in = in, .out = out };
}

test "areaVertexList" {
    print("\n", .{});

    var list_cw = [_]Vertex{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 2 },
        .{ .x = 2, .y = 2 },
        .{ .x = 2, .y = 0 },
    };

    var list_ccw = [_]Vertex{
        .{ .x = 0, .y = 0 },
        .{ .x = 2, .y = 0 },
        .{ .x = 2, .y = 2 },
        .{ .x = 0, .y = 2 },
    };

    const area_cw = try areaVertexList(&list_cw);
    const turns_cw = countTurns(&list_cw);
    print("Area  CW: {} {} {}\n", .{ area_cw, turns_cw.in, turns_cw.out });

    var area_ccw = areaVertexList(&list_ccw) catch 0;
    var turns_ccw = countTurns(&list_ccw);
    print("Area CCW: {} {} {}\n", .{ area_ccw, turns_ccw.in, turns_ccw.out });
}
