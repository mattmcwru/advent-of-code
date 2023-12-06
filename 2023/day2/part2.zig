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

        // Get the game id
        var game_tok = std.mem.tokenizeScalar(u8, line, ':');
        const game_id = game_tok.next();
        var game_id_num = try std.fmt.parseInt(u32, game_id.?[5..], 10);

        // Split the data into groups
        var group_tok = std.mem.tokenizeScalar(u8, game_tok.rest(), ';');

        var max_red_used: u32 = 0;
        var max_blue_used: u32 = 0;
        var max_green_used: u32 = 0;

        std.debug.print("Game {d:3} ", .{game_id_num});

        while (group_tok.next()) |group| {
            //std.debug.print(" <{s}> ", .{group});
            var cube_tok = std.mem.tokenizeScalar(u8, group, ',');

            while (cube_tok.next()) |cube| {
                var val_tok = std.mem.tokenizeScalar(u8, cube, ' ');
                const val = try std.fmt.parseInt(u32, val_tok.next().?, 10);
                var color = val_tok.next();
                const case = std.meta.stringToEnum(cube_colors, color.?);

                //std.debug.print(" {s} {d:3} ", .{ color.?, val });

                switch (case.?) {
                    .red => max_red_used = if (val > max_red_used) val else max_red_used,
                    .green => max_green_used = if (val > max_green_used) val else max_green_used,
                    .blue => max_blue_used = if (val > max_blue_used) val else max_blue_used,
                }
            }
        }

        var group_power = max_red_used * max_green_used * max_blue_used;
        total_sum += group_power;

        std.debug.print("{} {} {} {}\n", .{ max_red_used, max_green_used, max_blue_used, group_power });
    }

    std.debug.print("Total: {}\n", .{total_sum});
}
