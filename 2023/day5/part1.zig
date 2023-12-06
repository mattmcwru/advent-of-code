const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;

// const MapData = struct {
//     allocator: std.mem.allocator;
//     mapEntryList: std.MultiArrayList;

const MapInt: type = u64;

const MapEntry = struct {
    destination: MapInt,
    source: MapInt,
    length: MapInt,
};

const MapEntryList = std.MultiArrayList(MapEntry);

// pub fn init(allocator: std.mem.allocator) MapData {
//     allocator = allocator;
//     return
// }

// pub fn deinit() !void {

// }

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
        if (source >= s and source < s + len)
            return d + (source - s);
    }
    return source;
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
    for (seed_list.items) |seed| {
        print("Seed: {} => ", .{seed});
        const soil = searchMapData(seed_to_soil_map, seed);
        print("soil: {} => ", .{soil});
        const fertilizer = searchMapData(soil_to_fertilizer_map, soil);
        print("fertilizer: {} => ", .{fertilizer});
        const water = searchMapData(fertilizer_to_water_map, fertilizer);
        print("water: {} => ", .{water});
        const light = searchMapData(water_to_light_map, water);
        print("light: {} => ", .{light});
        const temperature = searchMapData(light_to_temperature_map, light);
        print("temperature: {} => ", .{temperature});
        const humidity = searchMapData(temperature_to_humidity_map, temperature);
        print("humidity: {} => ", .{humidity});
        const location = searchMapData(humidity_to_location_map, humidity);
        print("Location: {}\n", .{location});

        if (location < lowest_loc) lowest_loc = location;
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
