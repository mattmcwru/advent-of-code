const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;

const MapInt: type = u64;

const MapEntry = struct {
    destination: MapInt,
    source: MapInt,
    length: MapInt,
};

const MapEntryList = std.MultiArrayList(MapEntry);

// Parse a single map data entry (dest, src, len)
fn parseMapData(allocator: std.mem.Allocator, map: *MapEntryList, line: []const u8) !void {
    var data = std.mem.splitScalar(u8, line, ' ');

    const dst = if (data.next()) |d| try std.fmt.parseInt(MapInt, d, 10) else return error.InvalidInputData;
    const src = if (data.next()) |d| try std.fmt.parseInt(MapInt, d, 10) else return error.InvalidInputData;
    const len = if (data.next()) |d| try std.fmt.parseInt(MapInt, d, 10) else return error.InvalidInputData;

    try map.append(allocator, .{ .destination = dst, .source = src, .length = len });
}

// Return Destination for given Source
fn searchMapData(map: MapEntryList, source: MapInt) MapInt {
    for (map.items(.destination), map.items(.source), map.items(.length)) |d, s, len| {
        if (len > 0 and source >= s and source <= s + (len - 1))
            return d + (source - s);
    }
    return source;
}

// Return Destination for given Source
fn searchMapRange(allocator: std.mem.Allocator, map: MapEntryList, source: MapEntryList, destination: *MapEntryList) !void {
    for (source.items(.source), source.items(.length)) |src_s, src_len| {
        var i: MapInt = 0;
        //print("Src: {} {}\n", .{ src_s, src_len });

        while (i < src_len) {
            const seg_s = src_s + i;
            const seg_len = src_len - i;
            var seg_found = false;
            var frag_len = seg_len;

            // Find segment in map list
            for (map.items(.destination), map.items(.source), map.items(.length)) |map_d, map_s, map_len| {

                // Look for head contained or smallest fragment tail
                if (seg_s >= map_s and seg_s < map_s + map_len) {
                    const offset = seg_s - map_s;
                    const dst = map_d + offset;
                    const len = @min(seg_len, map_len - offset);

                    //print(" seg: {} => {} {}\n", .{ seg_s, dst, len });

                    try destination.append(allocator, .{ .destination = 0, .source = dst, .length = len });
                    i += len;
                    seg_found = true;
                } else if (map_s >= seg_s and map_s < seg_s + seg_len) {
                    frag_len = @min(frag_len, map_s - seg_s);
                }
            }

            // Segment not found in map list so add smallest fragment
            if (!seg_found) {
                //print("frag: {} => {} {}\n", .{ seg_s, seg_s, frag_len });
                try destination.append(allocator, .{ .destination = 0, .source = seg_s, .length = frag_len });
                i += frag_len;
            }
        }
    }
}

test "searchMapRange" {
    const allocator = std.testing.allocator;

    // Create seeds list
    var seeds_list = MapEntryList{};
    defer seeds_list.deinit(allocator);

    try seeds_list.append(allocator, .{ .destination = 0, .source = 79, .length = 14 });
    try seeds_list.append(allocator, .{ .destination = 0, .source = 40, .length = 30 });
    try seeds_list.append(allocator, .{ .destination = 0, .source = 79, .length = 21 });
    try seeds_list.append(allocator, .{ .destination = 0, .source = 0, .length = 120 });

    // Create seed to soil map
    const map_lines = [_][]const u8{ "50 98 2", "52 50 48" };
    var seed_to_soil_map = MapEntryList{};
    defer seed_to_soil_map.deinit(allocator);
    for (map_lines) |line| {
        try parseMapData(allocator, &seed_to_soil_map, line);
    }

    // Create soil list
    var soil_list = MapEntryList{};
    defer soil_list.deinit(allocator);

    print("\n", .{});

    try searchMapRange(allocator, seed_to_soil_map, seeds_list, &soil_list);

    print("\nSoil List\n", .{});

    for (soil_list.items(.destination), soil_list.items(.source), soil_list.items(.length)) |d, s, len| {
        print("{} {} {}\n", .{ d, s, len });
    }
}

fn parseSeedList(list: *std.ArrayList(MapInt), line: []const u8) !void {
    var data = std.mem.splitScalar(u8, line, ' ');

    // Pop and check header
    if (data.next()) |d| try expect(std.mem.eql(u8, d, "seeds:")) else return error.InvalidInputData;

    while (data.next()) |d| {
        try list.append(try std.fmt.parseInt(MapInt, d, 10));
    }
}

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    defer if (gpa.deinit() == .leak) expect(false) catch @panic("GPA Leaked Memory");

    const filename = getFileNameFromArgs(allocator) catch return;
    defer allocator.free(filename);

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var seed_list = std.ArrayList(MapInt).init(allocator);
    defer seed_list.deinit();

    var seed_to_soil_map = MapEntryList{};
    defer seed_to_soil_map.deinit(gpa_allocator);

    var soil_to_fertilizer_map = MapEntryList{};
    defer soil_to_fertilizer_map.deinit(gpa_allocator);

    var fertilizer_to_water_map = MapEntryList{};
    defer fertilizer_to_water_map.deinit(gpa_allocator);

    var water_to_light_map = MapEntryList{};
    defer water_to_light_map.deinit(gpa_allocator);

    var light_to_temperature_map = MapEntryList{};
    defer light_to_temperature_map.deinit(gpa_allocator);

    var temperature_to_humidity_map = MapEntryList{};
    defer temperature_to_humidity_map.deinit(gpa_allocator);

    var humidity_to_location_map = MapEntryList{};
    defer humidity_to_location_map.deinit(gpa_allocator);

    var data_sequence: u8 = 0;
    var first_line_of_sequence: bool = true;
    var lowest_loc: MapInt = std.math.maxInt(MapInt);

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        print("{s}\n", .{line});

        // Data sequences are split by empty lines
        if (line.len == 0) {
            data_sequence += 1;
            first_line_of_sequence = true;
            continue;
        }

        // Process data for sequence
        switch (data_sequence) {
            0 => try parseSeedList(&seed_list, line),
            1 => if (!first_line_of_sequence) try parseMapData(gpa_allocator, &seed_to_soil_map, line) else try expect(std.mem.eql(u8, line, "seed-to-soil map:")),
            2 => if (!first_line_of_sequence) try parseMapData(gpa_allocator, &soil_to_fertilizer_map, line) else try expect(std.mem.eql(u8, line, "soil-to-fertilizer map:")),
            3 => if (!first_line_of_sequence) try parseMapData(gpa_allocator, &fertilizer_to_water_map, line) else try expect(std.mem.eql(u8, line, "fertilizer-to-water map:")),
            4 => if (!first_line_of_sequence) try parseMapData(gpa_allocator, &water_to_light_map, line) else try expect(std.mem.eql(u8, line, "water-to-light map:")),
            5 => if (!first_line_of_sequence) try parseMapData(gpa_allocator, &light_to_temperature_map, line) else try expect(std.mem.eql(u8, line, "light-to-temperature map:")),
            6 => if (!first_line_of_sequence) try parseMapData(gpa_allocator, &temperature_to_humidity_map, line) else try expect(std.mem.eql(u8, line, "temperature-to-humidity map:")),
            7 => if (!first_line_of_sequence) try parseMapData(gpa_allocator, &humidity_to_location_map, line) else try expect(std.mem.eql(u8, line, "humidity-to-location map:")),
            else => undefined,
        }

        first_line_of_sequence = false;
    }

    // print("{any}\n", .{seed_list.items});
    // print("{any}\n", .{seed_to_soil_map});
    // print("{any}\n", .{soil_to_fertilizer_map});
    // print("{any}\n", .{fertilizer_to_water_map});
    // print("{any}\n", .{water_to_light_map});
    // print("{any}\n", .{light_to_temperature_map});
    // print("{any}\n", .{temperature_to_humidity_map});
    // print("{any}\n", .{humidity_to_location_map});

    print("\n", .{});

    // Compute results from collected data
    var i: u32 = 0;
    var seeds_list = MapEntryList{};
    defer seeds_list.deinit(gpa_allocator);

    while (i < seed_list.items.len) : (i += 2) {
        const start = seed_list.items[i];
        const lenth = seed_list.items[i + 1];

        try seeds_list.append(gpa_allocator, .{ .destination = 0, .source = start, .length = lenth });
    }

    //print("Soil:\n", .{});
    var soil_list = MapEntryList{};
    defer soil_list.deinit(gpa_allocator);
    try searchMapRange(gpa_allocator, seed_to_soil_map, seeds_list, &soil_list);

    //print("Fertilizer:\n", .{});
    var fertilizer_list = MapEntryList{};
    defer fertilizer_list.deinit(gpa_allocator);
    try searchMapRange(gpa_allocator, soil_to_fertilizer_map, soil_list, &fertilizer_list);

    //print("Water:\n", .{});
    var water_list = MapEntryList{};
    defer water_list.deinit(gpa_allocator);
    try searchMapRange(gpa_allocator, fertilizer_to_water_map, fertilizer_list, &water_list);

    //print("Light:\n", .{});
    var light_list = MapEntryList{};
    defer light_list.deinit(gpa_allocator);
    try searchMapRange(gpa_allocator, water_to_light_map, water_list, &light_list);

    //print("Temperature:\n", .{});
    var temperature_list = MapEntryList{};
    defer temperature_list.deinit(gpa_allocator);
    try searchMapRange(gpa_allocator, light_to_temperature_map, light_list, &temperature_list);

    //print("Humidity:\n", .{});
    var humidity_list = MapEntryList{};
    defer humidity_list.deinit(gpa_allocator);
    try searchMapRange(gpa_allocator, temperature_to_humidity_map, temperature_list, &humidity_list);

    //print("Location:\n", .{});
    var location_list = MapEntryList{};
    defer location_list.deinit(gpa_allocator);
    try searchMapRange(gpa_allocator, humidity_to_location_map, humidity_list, &location_list);

    print("Locations:\n", .{});
    for (location_list.items(.source), location_list.items(.length)) |s, len| {
        print("{} {}\n", .{ s, len });
        lowest_loc = @min(lowest_loc, s);
    }

    print("\nLowest Location: {}\n", .{lowest_loc});
}

// Must free returned string
fn getFileNameFromArgs(allocator: std.mem.Allocator) ![]u8 {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Error: Missing file argument\n\n", .{});
        std.debug.print("Usage: zig run part1.zig -- <filename>\n", .{});
        return error.FileNotFound;
    }

    const filename = try allocator.alloc(u8, args[1].len);
    errdefer allocator.free(filename);

    std.mem.copy(u8, filename, args[1]);

    return filename;
}
