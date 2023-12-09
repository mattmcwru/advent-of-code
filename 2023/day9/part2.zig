const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink

const DataType = i32;

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

    var data_list = std.ArrayList(DataType).init(allocator);
    defer data_list.deinit();

    var total_val: DataType = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var split_line = std.mem.splitScalar(u8, line, ' ');

        // Make sure the data list is empty
        data_list.clearRetainingCapacity();

        // Parse the line data
        while (split_line.next()) |val| {
            const val_int = try std.fmt.parseInt(DataType, val, 10);
            try data_list.append(val_int);
            print("{d} ", .{val_int});
        }

        // Process the data
        const ex_val = try processData(allocator, &data_list);
        print(" | ex_val = {}\n", .{ex_val});

        total_val += ex_val;
    }
    print("Total = {}\n", .{total_val});
}

pub fn processData(allocator: std.mem.Allocator, data_list: *const std.ArrayList(DataType)) !DataType {
    if (data_list.items.len == 0) return error.EmptyList;

    var diff_list = try std.ArrayList(DataType).initCapacity(allocator, data_list.items.len - 1);
    defer diff_list.deinit();

    var all_zero = true;
    var prev_val = data_list.items[0];

    for (data_list.items[1..]) |val| {
        var diff: DataType = val - prev_val;
        if (diff != 0) all_zero = false;
        try diff_list.append(diff);
        prev_val = val;
    }

    return if (all_zero) data_list.getLast() else data_list.items[0] - try processData(allocator, &diff_list);
}

test "processData" {
    print("\n", .{});
    const allocator = std.testing.allocator;

    var list = std.ArrayList(DataType).init(allocator);
    defer list.deinit();

    try list.append(0);
    try list.append(3);
    try list.append(6);
    try list.append(9);
    try list.append(12);
    try list.append(15);

    for (list.items) |val| {
        print("{} ", .{val});
    }
    print("\n", .{});

    const result = try processData(allocator, &list);
    print("Result: {}\n", .{result});
    try (expect(result == -3));
}
