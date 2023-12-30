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

    var modules_list = ModuleList.init(allocator);
    defer modules_list.deinit();

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

            try modules_list.list.put(module.mod_name, module);
        } else return error.ModuleNameNotFound;
    }

    // Find the input sources for conjunction modules
    try modules_list.updateConjunctionList();

    // Print the modules list
    modules_list.printList();

    const src_list = try modules_list.findSource("kh");
    defer allocator.free(src_list);
    print("Src List: {s}\n", .{src_list});

    // Push the button
    var pulse_stack = std.ArrayList(Pulse).init(allocator);
    defer pulse_stack.deinit();

    const button_presses: usize = 10000;
    var total_button_presses: usize = 0;

    var state_map = std.AutoHashMap(u128, []bool).init(allocator);
    defer {
        var state_iter = state_map.valueIterator();
        while (state_iter.next()) |it| {
            allocator.free(it.*);
        }
        state_map.deinit();
    }

    const state_size = getStateSize(&modules_list);
    print("State Size {}\n", .{state_size});

    var last_xm_press: usize = 0;
    var last_hz_press: usize = 0;
    var last_pv_press: usize = 0;
    var last_qh_press: usize = 0;

    var xm_cycle: usize = 0;
    var hz_cycle: usize = 0;
    var pv_cycle: usize = 0;
    var qh_cycle: usize = 0;

    button_loop: for (0..button_presses) |press_i| {

        // if ((press_i + 1) % 100000 == 0)
        //     print("\nPushing the button {}\n", .{press_i + 1});

        total_button_presses += 1;

        if (modules_list.list.get("kh")) |kh_mod| {
            var print_line = false;
            var val_iter = kh_mod.src_list.valueIterator();
            while (val_iter.next()) |src| {
                if (src.*) {
                    print_line = true;
                    break;
                }
            }
            if (print_line) {
                var iter = kh_mod.src_list.iterator();
                while (iter.next()) |src| {
                    print("{s}: {:5}, ", .{ src.key_ptr.*, src.value_ptr.* });
                }
                print("\n", .{});
            }
        }

        // Get current state of system
        //var system_state = try getSystemState(allocator, &modules_list, state_size);
        // _ = system_state;
        //defer allocator.free(system_state);

        // var state_key: u128 = 0;
        // var state_mask: u128 = 1;
        // for (system_state) |i| {
        //     if (i) state_key |= state_mask;
        //     state_mask <<= 1;
        // }
        // print("{x:0>16}\n", .{state_key});

        // for (system_state) |i| {
        //     print("{s}", .{if (i) "1" else "0"});
        // }
        // if (state_map.contains(state_key)) {
        //     print("{x:0>16}", .{state_key});
        //     print(" In Map\n", .{});
        //     allocator.free(system_state);
        // } else {
        //     //print(" Add to Map\n", .{});
        //     try state_map.put(state_key, system_state);
        // }
        //print("\n", .{});

        // // var mod_iter = modules_list.valueIterator();
        // while (mod_iter.next()) |module| {
        //     switch (module.mod_type) {
        //         .broadcaster => {},
        //         .flipflop => {
        //             print("{s} {s}\n", .{ module.mod_name, if (module.state) "high" else "low" });
        //         },
        //         .conjunction => {
        //             print("{s} {s}, ", .{ module.mod_name, if (module.state) "high" else "low" });

        //             var src_iter = module.src_list.valueIterator();
        //             while (src_iter.next()) |src_state| {
        //                 print("{s}, ", .{if (src_state.*) "high" else "low"});
        //             }
        //             print("\n", .{});
        //         },
        //     }
        // }

        // Add button press to pulse stack
        try pulse_stack.append(.{ .state = false, .src = "button", .dest = "broadcaster" });

        // Process pulses
        while (pulse_stack.popOrNull()) |pulse| {
            // Check for low pulse to rx

            if (pulse.state == false and std.mem.eql(u8, pulse.dest, "rx")) {
                print("break loop\n", .{});
                break :button_loop;
            }

            if (modules_list.list.getPtr(pulse.dest)) |module| {
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

                        if (pulse.state == true and std.mem.eql(u8, module.mod_name, "kh")) {
                            if (std.mem.eql(u8, pulse.src, "xm")) {
                                xm_cycle = press_i - last_xm_press;
                                print("  Conjunction: {s} {} {}\n", .{ pulse.src, pulse.state, xm_cycle });
                                last_xm_press = press_i;
                            }
                            if (std.mem.eql(u8, pulse.src, "qh")) {
                                qh_cycle = press_i - last_qh_press;
                                print("  Conjunction: {s} {} {}\n", .{ pulse.src, pulse.state, qh_cycle });
                                last_qh_press = press_i;
                            }
                            if (std.mem.eql(u8, pulse.src, "pv")) {
                                pv_cycle = press_i - last_pv_press;
                                print("  Conjunction: {s} {} {}\n", .{ pulse.src, pulse.state, pv_cycle });
                                last_pv_press = press_i;
                            }
                            if (std.mem.eql(u8, pulse.src, "hz")) {
                                hz_cycle = press_i - last_hz_press;
                                print("  Conjunction: {s} {} {}\n", .{ pulse.src, pulse.state, hz_cycle });
                                last_hz_press = press_i;
                            }
                        }

                        //     print("  Conjunction: {s} {} {}\n", .{ pulse.src, pulse.state, press_i });
                        // }

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

    print("\nTotal Button Presses {}\n", .{total_button_presses});

    const rx_presses = lcm(lcm(lcm(xm_cycle, hz_cycle), pv_cycle), qh_cycle);
    print("hz: {}, pv: {}, qh: {}, xm: {}\n", .{ hz_cycle, pv_cycle, qh_cycle, xm_cycle });
    print("RX Presses: {}\n", .{rx_presses});
}

pub fn lcm(m: usize, n: usize) usize {
    return m / std.math.gcd(m, n) * n;
}

const ModuleList = struct {
    list: List,
    allocator: std.mem.Allocator,

    const List = std.StringHashMap(Module);

    pub fn init(allocator: std.mem.Allocator) ModuleList {
        return .{ .list = List.init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *ModuleList) void {
        var iter = self.list.valueIterator();
        while (iter.next()) |it| {
            it.deinit();
        }
        self.list.deinit();
    }

    pub fn updateConjunctionList(self: ModuleList) !void {
        var iter = self.list.valueIterator();
        while (iter.next()) |module| {
            if (module.mod_type == .conjunction) {
                if (self.list.getPtr(module.mod_name)) |con_mod| {
                    var con_iter = self.list.valueIterator();
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
        }
    }

    pub fn printList(self: ModuleList) void {
        var iter = self.list.valueIterator();
        while (iter.next()) |module| {
            module.printModule();

            // print("{s} : {s} -> ", .{ module.mod_name, @tagName(module.mod_type) });
            // for (module.dest_list.items) |dest_name| {
            //     print("{s}, ", .{dest_name});
            // }
            // print("\n", .{});
        }
    }

    pub fn findSource(self: ModuleList, target: []const u8) ![]Module.ModuleName {
        var src_list = std.ArrayList(Module.ModuleName).init(self.allocator);

        var iter = self.list.valueIterator();
        while (iter.next()) |module| {
            for (module.dest_list.items) |dest| {
                if (std.mem.eql(u8, dest, target)) {
                    print("Found {s} in {s}\n", .{ dest, module.mod_name });
                    try src_list.append(module.mod_name);
                }
            }
        }
        return try src_list.toOwnedSlice();
    }
};

const Module = struct {
    mod_name: ModuleName,
    mod_type: ModuleType,
    state: bool,
    src_list: ModuleSourceList,
    dest_list: ModuleDestList,
    allocator: std.mem.Allocator,

    const ModuleName = []const u8;
    const ModuleType = enum { broadcaster, flipflop, conjunction };
    const ModuleDestList = std.ArrayList(ModuleName);
    const ModuleSourceList = std.StringHashMap(bool);

    pub fn init(allocator: std.mem.Allocator, mod_name: []const u8, mod_type: ModuleType) !Module {
        return .{
            .mod_name = try allocator.dupe(u8, mod_name),
            .mod_type = mod_type,
            .state = false,
            .src_list = ModuleSourceList.init(allocator),
            .dest_list = ModuleDestList.init(allocator),
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

    pub fn printModule(self: Module) void {
        print("{s} : {s} -> ", .{ self.mod_name, @tagName(self.mod_type) });
        for (self.dest_list.items) |dest_name| {
            print("{s}, ", .{dest_name});
        }
        print("\n", .{});
    }
};

const Pulse = struct {
    state: bool,
    src: Module.ModuleName,
    dest: Module.ModuleName,
};

pub fn getStateSize(list: *const ModuleList) usize {
    var state_size: usize = 0;
    var mod_iter = list.list.valueIterator();
    while (mod_iter.next()) |module| {
        switch (module.mod_type) {
            .broadcaster => {},
            .flipflop => {
                state_size += 1;
            },
            .conjunction => {
                state_size += 1;

                var src_iter = module.src_list.valueIterator();
                while (src_iter.next()) |_| {
                    state_size += 1;
                }
            },
        }
    }
    return state_size;
}

pub fn getSystemState(allocator: std.mem.Allocator, list: *const ModuleList, state_size: usize) ![]bool {
    var state_list: []bool = try allocator.alloc(bool, state_size);
    var state_index: usize = 0;

    // Get current state of system
    var mod_iter = list.list.valueIterator();
    while (mod_iter.next()) |module| {
        switch (module.mod_type) {
            .broadcaster => {},
            .flipflop => {
                state_list[state_index] = module.state;
                state_index += 1;
            },
            .conjunction => {
                state_list[state_index] = module.state;
                state_index += 1;

                var src_iter = module.src_list.valueIterator();
                while (src_iter.next()) |src_state| {
                    state_list[state_index] = src_state.*;
                    state_index += 1;
                }
            },
        }
    }

    return state_list;
}
