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

    var modules_list = std.StringHashMap(Module).init(allocator);
    defer {
        var iter = modules_list.valueIterator();
        while (iter.next()) |it| {
            it.deinit();
        }
        modules_list.deinit();
    }

    // Parse the workflow list
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var toks = std.mem.tokenizeAny(u8, line, " ->,");

        // Get module name and type
        if (toks.next()) |name| {
            var ni: usize = 0;
            var mod_type: Module.ModuleType = undefined;
            if (std.mem.eql(u8, name, "broadcaster")) {
                mod_type = .broadcaster;
            } else {
                ni = 1;
                mod_type = switch (name[0]) {
                    '%' => .flipflop,
                    '&' => .conjunction,
                    else => return error.BadModuleType,
                };
            }

            var module = try Module.init(allocator, name[ni..], mod_type);
            errdefer module.deinit();

            // Add destination list to module
            while (toks.next()) |dest| {
                try module.addDest(dest);
            }

            try modules_list.put(module.mod_name, module);
        } else return error.ModuleNameNotFound;
    }

    // Find the input sources for conjunction modules
    var iter = modules_list.valueIterator();
    while (iter.next()) |module| {
        if (module.mod_type == .conjunction) {
            if (modules_list.getPtr(module.mod_name)) |con_mod| {
                var con_iter = modules_list.valueIterator();
                while (con_iter.next()) |mod| {
                    for (mod.dest_list.items) |dest| {
                        if (std.mem.eql(u8, dest, module.mod_name)) {
                            //print("Added {s} to {s} source list\n", .{ mod.mod_name, con_mod.mod_name });
                            try con_mod.src_list.put(mod.mod_name, false);
                        }
                    }
                }
            }
        }

        // Print the module
        print("{s} : {s} -> ", .{ module.mod_name, @tagName(module.mod_type) });
        for (module.dest_list.items) |dest_name| {
            print("{s}, ", .{dest_name});
        }
        print("\n", .{});
    }

    // Push the button
    var pulse_stack = std.ArrayList(Pulse).init(allocator);
    defer pulse_stack.deinit();

    const button_presses: usize = 1000;

    var total_low_pulses: usize = 0;
    var total_high_pulses: usize = 0;

    for (0..button_presses) |press_i| {
        print("\nPushing the button {}\n", .{press_i + 1});

        // Add button press to pulse stack
        try pulse_stack.append(.{ .state = false, .src = "button", .dest = "broadcaster" });

        // Process pulses
        while (pulse_stack.popOrNull()) |pulse| {
            if (pulse.state) total_high_pulses += 1 else total_low_pulses += 1;

            print("Pulse: {s} {s} -> {s}\n", .{ if (pulse.state) "high" else " low", pulse.src, pulse.dest });

            if (modules_list.getPtr(pulse.dest)) |module| {
                switch (module.mod_type) {
                    .broadcaster => {
                        for (module.dest_list.items) |mod_dest| {
                            try pulse_stack.insert(0, .{ .state = pulse.state, .src = pulse.dest, .dest = mod_dest });
                        }
                    },
                    .flipflop => {
                        if (pulse.state == false) {
                            module.state = !module.state;
                            for (module.dest_list.items) |mod_dest| {
                                try pulse_stack.insert(0, .{ .state = module.state, .src = pulse.dest, .dest = mod_dest });
                            }
                        }
                    },
                    .conjunction => {
                        // Update input state
                        //print("  Conjunction: {s}\n", .{pulse.src});
                        if (module.src_list.getPtr(pulse.src)) |src_state| {
                            src_state.* = pulse.state;
                        } else return error.ConjumctionSourceInputNotFound;

                        // Determine pulse output state
                        var dest_state: bool = true;
                        var src_iter = module.src_list.valueIterator();
                        while (src_iter.next()) |src_state| {
                            if (!src_state.*) break;
                        } else {
                            dest_state = false;
                        }

                        // Send pulse to destination modules
                        for (module.dest_list.items) |mod_dest| {
                            try pulse_stack.insert(0, .{ .state = dest_state, .src = pulse.dest, .dest = mod_dest });
                        }
                    },
                }
            }
        }
    }
    print("\nTotal Pulses: {}  Low: {} High: {}\n", .{ total_low_pulses * total_high_pulses, total_low_pulses, total_high_pulses });
}

const Module = struct {
    mod_name: ModuleName,
    mod_type: ModuleType,
    state: bool,
    src_list: ModuleSourceList,
    dest_list: ModuleList,
    allocator: std.mem.Allocator,

    const ModuleName = []const u8;
    const ModuleType = enum { broadcaster, flipflop, conjunction };
    const ModuleList = std.ArrayList(ModuleName);
    const ModuleSourceList = std.StringHashMap(bool);

    pub fn init(allocator: std.mem.Allocator, mod_name: []const u8, mod_type: ModuleType) !Module {
        return .{
            .mod_name = try allocator.dupe(u8, mod_name),
            .mod_type = mod_type,
            .state = false,
            .src_list = ModuleSourceList.init(allocator),
            .dest_list = ModuleList.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Module) void {
        self.allocator.free(self.mod_name);
        self.src_list.deinit();
        for (self.dest_list.items) |dest_name| {
            self.allocator.free(dest_name);
        }
        self.dest_list.deinit();
    }

    pub fn addDest(self: *Module, dest_name: []const u8) !void {
        try self.dest_list.append(try self.allocator.dupe(u8, dest_name));
    }

    pub fn addSource(self: *Module, src_name: []const u8) !void {
        try self.src_list.put(src_name, false);
    }
};

const Pulse = struct {
    state: bool,
    src: Module.ModuleName,
    dest: Module.ModuleName,
};
