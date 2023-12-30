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

    var spring_list = std.ArrayList(SpringState).init(allocator);
    defer spring_list.deinit();
    var damaged_list = std.ArrayList(u8).init(allocator);
    defer damaged_list.deinit();
    var finder_cache = FinderCache.init(allocator);
    defer finder_cache.deinit();

    var total_arrangements: usize = 0;

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var split_line = std.mem.splitAny(u8, line, " ,");

        spring_list.clearRetainingCapacity();
        damaged_list.clearRetainingCapacity();
        finder_cache.clearCache();

        if (split_line.next()) |springs| {
            for (springs) |spring| {
                try spring_list.append(switch (spring) {
                    '.' => .working,
                    '#' => .damaged,
                    '?' => .unknown,
                    else => return error.BadSymbolInput,
                });
            }
        } else return error.MissingSpringList;

        while (split_line.next()) |damaged| {
            try damaged_list.append(try std.fmt.parseInt(u8, damaged, 10));
        }

        // Duplicate lists
        const repeats: usize = 5;

        try spring_list.ensureTotalCapacity((spring_list.items.len + 1) * repeats);
        try damaged_list.ensureTotalCapacity(damaged_list.items.len * repeats);
        const spring_items = spring_list.items;
        const damaged_items = damaged_list.items;
        for (1..repeats) |_| {
            spring_list.appendAssumeCapacity(.unknown);
            spring_list.appendSliceAssumeCapacity(spring_items);
            damaged_list.appendSliceAssumeCapacity(damaged_items);
        }

        var spring_slice = try spring_list.toOwnedSlice();
        defer allocator.free(spring_slice);
        var damaged_slice = try damaged_list.toOwnedSlice();
        defer allocator.free(damaged_slice);

        //print("{any} ", .{damaged_slice});
        //print_spring_list(spring_slice);

        const arrangements = try findArrangements(spring_slice, damaged_slice, &finder_cache, 0);

        //print("Arrangements: {}  ", .{arrangements});
        //print_spring_list(spring_slice);
        //print("\n", .{});

        total_arrangements += arrangements;
    }
    print("\nTotal Arrangements: {}\n", .{total_arrangements});
}

const SpringState = enum { working, damaged, unknown };
const SpringList = []SpringState;
const DamagedList = []u8;

const FinderCache = struct {
    cache: Cache,
    allocator: std.mem.Allocator,

    const Cache = std.HashMap(FinderKey, usize, FinderKey.FinderKeyCtx, std.hash_map.default_max_load_percentage);

    const FinderKey = struct {
        spring_list: SpringList,
        damage_list: DamagedList,

        const FinderKeyCtx = struct {
            pub fn hash(_: FinderKeyCtx, key: FinderKey) u64 {
                var h = std.hash.Wyhash.init(0xDEADBEEF);
                for (key.spring_list) |spring| {
                    h.update(switch (spring) {
                        .working => ".",
                        .damaged => "#",
                        .unknown => "?",
                    });
                }
                h.update(key.damage_list);
                return h.final();
            }

            pub fn eql(_: FinderKeyCtx, a: FinderKey, b: FinderKey) bool {
                return std.mem.eql(SpringState, a.spring_list, b.spring_list) and std.mem.eql(u8, a.damage_list, b.damage_list);
            }
        };

        pub fn deinit(self: FinderKey, allocator: std.mem.Allocator) void {
            allocator.free(self.spring_list);
            allocator.free(self.damage_list);
        }
    };

    pub fn init(allocator: std.mem.Allocator) FinderCache {
        return .{ .cache = Cache.init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *FinderCache) void {
        var iter = self.cache.keyIterator();
        while (iter.next()) |key| {
            key.deinit(self.allocator);
        }
        self.cache.deinit();
    }

    pub fn clearCache(self: *FinderCache) void {
        var iter = self.cache.keyIterator();
        while (iter.next()) |key| {
            key.deinit(self.allocator);
        }
        self.cache.clearRetainingCapacity();
    }

    pub fn createKey(self: FinderCache, spring_list: SpringList, damage_list: DamagedList) !FinderKey {
        return .{
            .spring_list = try self.allocator.dupe(SpringState, spring_list),
            .damage_list = try self.allocator.dupe(u8, damage_list),
        };
    }

    pub fn get(self: FinderCache, spring_list: SpringList, damage_list: DamagedList) ?usize {
        return self.cache.get(.{ .spring_list = spring_list, .damage_list = damage_list });
    }
};

pub fn findArrangements(spring_list: SpringList, damaged_list: DamagedList, finder_cache: *FinderCache, depth: usize) !usize {
    if (spring_list.len == 0) {
        //print("{}: Spring List zero\n", .{depth});
        return if (damaged_list.len == 0) 1 else 0;
    }

    if (damaged_list.len == 0) {
        //print("{}: Damage List zero\n", .{depth});
        return if (std.mem.containsAtLeast(SpringState, spring_list, 1, &[_]SpringState{.damaged})) 0 else 1;
    }

    if (damaged_list[0] > spring_list.len) {
        return 0;
    }

    if (finder_cache.get(spring_list, damaged_list)) |val| {
        //print("Found cache key\n", .{});
        return val;
    }

    var arrangements: usize = 0;

    if (spring_list[0] == .working or spring_list[0] == .unknown) {
        // print("{}: Check working [{},{}]: ", .{ depth, damaged_list[0], spring_list.len });
        // print_spring_list(spring_list[1..]);
        arrangements += try findArrangements(spring_list[1..], damaged_list, finder_cache, depth + 1);
    }

    if (spring_list[0] == .damaged or spring_list[0] == .unknown) {
        // print("{}: Check damaged: ", .{depth});
        // print_spring_list(spring_list);

        // print("{}:  {}, {}, {}\n", .{
        //     depth,
        //     spring_list.len >= damaged_list[0],
        //     !std.mem.containsAtLeast(SpringState, spring_list[0..damaged_list[0]], 1, &[_]SpringState{.working}),
        //     (spring_list.len == damaged_list[0]) or (spring_list[damaged_list[0]] != .damaged),
        // });

        if ((spring_list.len >= damaged_list[0]) and
            (!std.mem.containsAtLeast(SpringState, spring_list[0..damaged_list[0]], 1, &[_]SpringState{.working})))
        {
            if (spring_list.len == damaged_list[0] or
                (spring_list.len == damaged_list[0] + 1 and spring_list[damaged_list[0]] != .damaged))
            {
                //print("{}:   Damage {}: none\n", .{ depth, damaged_list[0] });
                arrangements += try findArrangements(&[_]SpringState{}, damaged_list[1..], finder_cache, depth + 1);
            } else if (spring_list[damaged_list[0]] != .damaged) {
                // print("{}:   Damage {}: ", .{ depth, damaged_list[0] });
                // print_spring_list(spring_list[damaged_list[0] + 1 ..]);
                arrangements += try findArrangements(spring_list[damaged_list[0] + 1 ..], damaged_list[1..], finder_cache, depth + 1);
            }
        }
    }

    const cache_key = try finder_cache.createKey(spring_list, damaged_list);
    errdefer cache_key.deinit(finder_cache.allocator);

    try finder_cache.cache.put(cache_key, arrangements);

    return arrangements;
}

pub fn print_spring_list(springs: SpringList) void {
    for (springs) |spring| {
        switch (spring) {
            .working => print(".", .{}),
            .damaged => print("#", .{}),
            .unknown => print("?", .{}),
        }
    }
    //    print("\n", .{});
}
