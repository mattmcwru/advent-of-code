const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const getFileNameFromArgs = @import("libs/args.zig").getFileNameFromArgs; // "libs/" points to "../../libs/" via a symlink
const Allocator = std.mem.Allocator;

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

    var component_list = ComponentList.init(allocator);
    defer component_list.deinit();

    // Collect all data from input file
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var toks = std.mem.tokenizeAny(u8, line, ": ");

        var base_component_name: ComponentNameHash = undefined;

        if (toks.next()) |name| {
            // If component name not in list then add new one
            if (!component_list.containsName(name)) {
                try component_list.putName(name, Component.init(allocator, name));
            }
            base_component_name = Component.nameHash(name);
        } else return error.MissingBaseComponent;

        while (toks.next()) |name| {
            // If component name is not in list then add new one
            if (!component_list.containsName(name)) {
                try component_list.putName(name, Component.init(allocator, name));
            }

            // Add links to both components
            if (component_list.getNamePtr(name)) |component| {
                try component.addLink(base_component_name);

                if (component_list.getPtr(base_component_name)) |base_component| {
                    try base_component.addLink(component.name);
                } else return error.ComponentMissingFromList;
            } else return error.ComponentMissingFromList;
        }
    }

    // Print out nodes
    var iter = component_list.list.valueIterator();
    while (iter.next()) |component| {
        var component_str = try component.getNameStr();
        defer allocator.free(component_str);

        print("{} {s} | ", .{ component.name, component_str });

        if (component.links) |links_list| {
            var links_iter = links_list.keyIterator();
            while (links_iter.next()) |link_name| {
                if (component_list.list.get(link_name.*)) |link| {
                    var link_str = try link.getNameStr();
                    defer allocator.free(link_str);

                    print(" {} {s},", .{ link.name, link_str });
                }
            }
        }
        print("\n", .{});
    }
    print("\n", .{});

    try component_list.findMostTraveledPaths();
}

const ComponentNameHash = u24;

const ComponentList = struct {
    list: List,
    allocator: Allocator,

    const List = std.AutoHashMap(ComponentNameHash, Component);

    pub fn init(allocator: Allocator) ComponentList {
        return .{
            .list = List.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ComponentList) void {
        var iter = self.list.valueIterator();
        while (iter.next()) |component| {
            component.deinit();
        }
        self.list.deinit();
    }

    pub fn containsName(self: ComponentList, name: []const u8) bool {
        return self.list.contains(Component.nameHash(name));
    }

    pub fn putName(self: *ComponentList, name: []const u8, component: Component) !void {
        try self.list.put(Component.nameHash(name), component);
    }

    pub fn getNamePtr(self: ComponentList, name: []const u8) ?*Component {
        return self.list.getPtr(Component.nameHash(name));
    }

    pub fn getPtr(self: ComponentList, hash: ComponentNameHash) ?*Component {
        return self.list.getPtr(hash);
    }

    const SearchNode = struct {
        name: ComponentNameHash,
        prev: ?ComponentNameHash,

        pub fn init(name: ComponentNameHash, prev: ?ComponentNameHash) SearchNode {
            return .{ .name = name, .prev = prev };
        }
    };

    const Edge = struct {
        nodes: [2]ComponentNameHash,

        pub fn orderdNodes(a: ComponentNameHash, b: ComponentNameHash) Edge {
            return .{ .nodes = .{ @min(a, b), @max(a, b) } };
        }

        pub fn printEdgeName(self: Edge, allocator: Allocator) !void {
            var node0_str = try Component.hashToName(self.nodes[0], allocator);
            defer allocator.free(node0_str);

            var node1_str = try Component.hashToName(self.nodes[1], allocator);
            defer allocator.free(node1_str);

            print("{s}-{s}", .{ node0_str, node1_str });
        }
    };

    const EdgeSortCtx = struct {
        values: []usize,

        pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
            return ctx.values[a_index] > ctx.values[b_index];
        }
    };

    pub fn findMostTraveledPaths(self: ComponentList) !void {
        var search_queue = std.ArrayList(SearchNode).init(self.allocator);
        defer search_queue.deinit();
        var done_list = std.AutoHashMap(ComponentNameHash, SearchNode).init(self.allocator);
        defer done_list.deinit();
        var edges_list = std.AutoArrayHashMap(Edge, usize).init(self.allocator);
        defer edges_list.deinit();

        // Find paths for every node to every other node
        var components = self.list.keyIterator();
        while (components.next()) |starting_component| {
            search_queue.clearRetainingCapacity();
            done_list.clearRetainingCapacity();

            // Add first component to the search list
            try search_queue.append(SearchNode.init(starting_component.*, null));

            // BFS to find paths to all nodes
            while (search_queue.popOrNull()) |node| {
                // Skip if already in done list
                if (done_list.contains(node.name)) continue;

                // Add node to done list
                try done_list.put(node.name, node);

                // Add linked componets to search queue
                if (self.list.get(node.name)) |component| {
                    if (component.links) |links| {
                        var link_iter = links.keyIterator();
                        while (link_iter.next()) |link_name| {
                            if (!done_list.contains(link_name.*)) {
                                try search_queue.insert(0, SearchNode.init(link_name.*, node.name));
                            }
                        }
                    }
                }
            }

            // Walk path from all nodes backwards to find edge counts
            var done_iter = done_list.valueIterator();
            while (done_iter.next()) |node| {
                var path_node = node.*;
                while (path_node.name != starting_component.*) {
                    if (done_list.get(path_node.prev.?)) |next_node| {
                        const edge = Edge.orderdNodes(path_node.name, next_node.name);
                        if (edges_list.getPtr(edge)) |edge_ptr| {
                            edge_ptr.* += 1;
                        } else {
                            try edges_list.put(edge, 1);
                        }
                        path_node = next_node;
                    } else return error.PathNodeNotFound;
                }
            }
        }

        // Sort the edge list
        edges_list.sort(EdgeSortCtx{ .values = edges_list.values() });

        // Print the edge counts
        var edge_iter = edges_list.iterator();
        var i: usize = 0;
        while (edge_iter.next()) |edge_node| : (i += 1) {
            const edge = edge_node.key_ptr.*;
            print("{:2}: ", .{i});
            try edge.printEdgeName(self.allocator);
            print(" = {}\n", .{edge_node.value_ptr.*});
        }
        print("\n", .{});

        const count_total = try self.countNodes(edges_list.keys()[0].nodes[0]);

        // Remove top three links
        try expect(edges_list.keys().len > 3);
        for (edges_list.keys()[0..3]) |key| {
            print("Removed ", .{});
            try key.printEdgeName(self.allocator);
            print("\n", .{});

            if (self.list.getPtr(key.nodes[0])) |n| {
                _ = n.removeLink(key.nodes[1]);
            } else return error.KeyNotFound;

            if (self.list.getPtr(key.nodes[1])) |n| {
                _ = n.removeLink(key.nodes[0]);
            } else return error.KeyNotFound;
        }

        // Count nodes in set
        const count_left = try self.countNodes(edges_list.keys()[0].nodes[0]);
        const count_right = try self.countNodes(edges_list.keys()[0].nodes[1]);
        print("\nLeft: {}, Right: {}, Total: {}, Result: {}\n", .{ count_left, count_right, count_total, count_left * count_right });
    }

    pub fn countNodes(self: ComponentList, start: ComponentNameHash) !List.Size {
        var search_queue = std.ArrayList(ComponentNameHash).init(self.allocator);
        defer search_queue.deinit();
        var done_list = std.AutoHashMap(ComponentNameHash, void).init(self.allocator);
        defer done_list.deinit();

        // Add first component to the search list
        try search_queue.append(start);

        // BFS to find paths to all nodes
        while (search_queue.popOrNull()) |node| {
            // Skip if already in done list
            if (done_list.contains(node)) continue;

            // Add node to done list
            try done_list.put(node, {});

            // Add linked componets to search queue
            if (self.list.get(node)) |component| {
                if (component.links) |links| {
                    var link_iter = links.keyIterator();
                    while (link_iter.next()) |link_name| {
                        if (!done_list.contains(link_name.*)) {
                            try search_queue.insert(0, link_name.*);
                        }
                    }
                }
            }
        }

        return done_list.count();
    }
};

const Component = struct {
    name: ComponentNameHash,
    links: ?ComponentLinkList,
    allocator: Allocator,

    const ComponentLinkList = std.AutoHashMap(ComponentNameHash, void);

    pub fn init(allocator: Allocator, name: []const u8) Component {
        return .{ .name = nameHash(name), .links = null, .allocator = allocator };
    }

    pub fn deinit(self: *Component) void {
        if (self.links) |*list| list.deinit();
    }

    pub fn nameHash(name: []const u8) ComponentNameHash {
        var hash: ComponentNameHash = 0;
        for (0..@min(3, name.len)) |i| {
            hash <<= 8;
            hash |= name[i];
        }
        return hash;
    }

    pub fn getNameStr(self: Component) ![]u8 {
        return hashToName(self.name, self.allocator);
    }

    pub fn hashToName(hash: ComponentNameHash, allocator: std.mem.Allocator) ![]u8 {
        var name = try allocator.alloc(u8, 3);
        name[0] = @as(u8, @intCast((hash >> 16) & 0xFF));
        name[1] = @as(u8, @intCast((hash >> 8) & 0xFF));
        name[2] = @as(u8, @intCast(hash & 0xFF));
        return name;
    }

    pub fn addLink(self: *Component, name: ComponentNameHash) !void {
        if (self.links == null) {
            self.links = ComponentLinkList.init(self.allocator);
        }
        if (self.links) |*list| {
            try list.put(name, {});
        } else {
            return error.LinksListNull;
        }
    }

    pub fn removeLink(self: *Component, name: ComponentNameHash) bool {
        return if (self.links) |*links| links.remove(name) else false;
    }
};
