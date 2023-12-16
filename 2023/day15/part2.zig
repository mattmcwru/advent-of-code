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

    var boxes = try Boxes.initCapacity(allocator, 256);
    for (0..256) |_| {
        try boxes.append(LensStack.init(allocator));
    }
    defer {
        for (boxes.items) |box| {
            for (box.items) |slot| {
                allocator.free(slot.label);
            }
            box.deinit();
        }
        boxes.deinit();
    }

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, ',')) |sequence| {
        const oper = try OperCode.init(sequence);
        const hash = run_hash(oper.label);
        //print("Parsing {s}...\n", .{sequence});

        switch (oper.oper) {
            .insert => {
                for (boxes.items[hash].items) |*lens| {
                    if (std.mem.eql(u8, lens.label, oper.label)) {
                        lens.fclen = oper.lens_fclen;
                        //print("Modifying \"{s} {}\" in Box {}\n", .{ oper.label, oper.lens_fclen, hash });
                        break;
                    }
                } else {
                    try boxes.items[hash].append(.{ .fclen = oper.lens_fclen, .label = try allocator.dupe(u8, oper.label) });
                    //print("Inserting \"{s} {}\" to Box {}\n", .{ oper.label, oper.lens_fclen, hash });
                }
            },
            .remove => {
                for (boxes.items[hash].items, 0..) |lens, i| {
                    if (std.mem.eql(u8, lens.label, oper.label)) {
                        //print("Removing \"{s}\" from Box {}\n", .{ oper.label, hash });
                        allocator.free(lens.label);
                        _ = boxes.items[hash].orderedRemove(i);
                        break;
                    }
                } else {
                    //print("\"{s}\" not found in Box {}\n", .{ oper.label, hash });
                }
            },
        }

        // for (boxes.items, 0..) |box, i| {
        //     if (box.items.len > 0) {
        //         print("Box {}: ", .{i});
        //         for (box.items) |lens| {
        //             print("{s} {}, ", .{ lens.label, lens.fclen });
        //         }
        //         print("\n", .{});
        //     }
        // }
        // print("\n", .{});
    }

    // for (boxes.items, 0..) |box, i| {
    //     for (box.items) |lens| {
    //         print("Box {}: {s} {}\n", .{ i, lens.label, lens.fclen });
    //     }
    // }

    // Calculate Power
    var total_power: usize = 0;
    for (boxes.items, 0..) |box, box_num| {
        for (box.items, 1..) |lens, slot| {
            const power = (1 + box_num) * slot * lens.fclen;
            total_power += power;
            print("Box {:3}-{}: {:4} {s}\n", .{ box_num, slot, power, lens.label });
        }
    }

    print("\nTotal Sum is {}\n", .{total_power});
}

pub fn run_hash(string: []const u8) u8 {
    var sum: u16 = 0;
    for (string) |c| {
        sum = @mod((sum + c) * 17, 256);
    }
    return std.mem.toBytes(sum)[0];
}

test "run_hash" {
    const hval = run_hash("HASH");
    try expect(hval == 52);
    print("{}\n", .{hval});
}

const OperCode = struct {
    lens_fclen: u8,
    oper: Oper,
    label: []const u8,

    const Oper = enum { remove, insert };

    pub fn init(sequence: []const u8) !OperCode {
        const is_last_digit = std.ascii.isDigit(sequence[sequence.len - 1]);
        const oper_code = if (is_last_digit) sequence[sequence.len - 2] else sequence[sequence.len - 1];
        return .{
            .lens_fclen = if (is_last_digit) sequence[sequence.len - 1] - '0' else 0,
            .label = if (is_last_digit) sequence[0 .. sequence.len - 2] else sequence[0 .. sequence.len - 1],
            .oper = switch (oper_code) {
                '=' => .insert,
                '-' => .remove,
                else => return error.BadSymbol,
            },
        };
    }
};

const Lens = struct {
    fclen: u8,
    label: []const u8,
};

const LensStack = std.ArrayList(Lens);

const Boxes = std.ArrayList(LensStack);
