const std = @import("std");

var red_max: u32 = 12;
var green_max: u32 = 13;
var blue_max: u32 = 14;

pub fn main() !void {
    var total_sum: u32 = 0;
    const cube_colors = enum { red, green, blue };

    var file = try std.fs.cwd().openFile("data.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var gg: bool = true;

        // Get the game id
        var game_tok = std.mem.tokenizeScalar(u8, line, ':');
        const game_id = game_tok.next();
        var game_id_num = try std.fmt.parseInt(u32, game_id.?[5..], 10);
        std.debug.print("Game {d:3} ", .{game_id_num});

        // Split the data into groups
        var group_tok = std.mem.tokenizeScalar(u8, game_tok.rest(), ';');

        while (group_tok.next()) |group| {
            //std.debug.print(" <{s}> ", .{group});
            var cube_tok = std.mem.tokenizeScalar(u8, group, ',');

            while (cube_tok.next()) |cube| {
                var val_tok = std.mem.tokenizeScalar(u8, cube, ' ');
                const val = try std.fmt.parseInt(u32, val_tok.next().?, 10);
                var color = val_tok.next();
                const case = std.meta.stringToEnum(cube_colors, color.?);

                std.debug.print(" {s:5} {d:3} ", .{ color.?, val });

                switch (case.?) {
                    .red => if (val > red_max) {
                        gg = false;
                        break;
                    },
                    .green => if (val > green_max) {
                        gg = false;
                        break;
                    },
                    .blue => if (val > blue_max) {
                        gg = false;
                        break;
                    },
                }
            }
            std.debug.print(" | ", .{});
        }

        // Check if good or over
        if (gg) {
            total_sum += game_id_num;
            std.debug.print(" good", .{});
        } else {
            std.debug.print(" over", .{});
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("Total: {}\n", .{total_sum});
}
