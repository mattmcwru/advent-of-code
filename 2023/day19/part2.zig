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

    var wf_list = WorkflowList.init(allocator);
    defer wf_list.deinit();

    var i: usize = 0;

    // Parse the workflow list
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (line.len == 0) break;
        var toks = std.mem.tokenizeAny(u8, line, "{},");
        print("{:2}: ", .{i});

        var wf: Workflow = undefined;

        // Capture workflow name
        if (toks.next()) |name| {
            wf = try Workflow.init(allocator, name);
        } else return error.MissingWorkflowName;

        // Capture the workflow rules
        while (toks.next()) |t| {
            print("{s} ", .{t});
            var rule_toks = std.mem.splitBackwardsScalar(u8, t, ':');

            var rule = try wf.appendRule(if (rule_toks.next()) |name| name else return error.MissingRuleName);

            if (rule_toks.next()) |op| {
                try expect(op.len > 3);
                rule.*.setInstruction(
                    switch (op[0]) {
                        'x' => .x,
                        'm' => .m,
                        'a' => .a,
                        's' => .s,
                        else => undefined,
                    },
                    switch (op[1]) {
                        '>' => .gt,
                        '<' => .lt,
                        else => undefined,
                    },
                    try std.fmt.parseInt(usize, op[2..], 10),
                );
            }
        }

        if (wf_list.workflows.contains(wf.name)) {
            return error.WorkflowNameDuplicate;
        }
        try wf_list.workflows.put(wf.name, wf);
        i += 1;
        print("\n", .{});
    }

    print("\n", .{});

    // Print rules
    var iter = wf_list.workflows.valueIterator();
    while (iter.next()) |wf| {
        print("{s:3} | ", .{wf.name});
        for (wf.rules.items) |r| {
            if (r.instruction) |inst| {
                print("{s} {s} {} : ", .{ @tagName(inst.cat), @tagName(inst.op), inst.val });
            }
            print("{s}, ", .{r.target});
        }
        print("\n", .{});
    }
    print("\n", .{});

    // Find Acceptable Ranges
    const start_range = CategoryRange{
        .x = .{ .min = 1, .max = 4000 },
        .m = .{ .min = 1, .max = 4000 },
        .a = .{ .min = 1, .max = 4000 },
        .s = .{ .min = 1, .max = 4000 },
    };

    var path_stack = PathList.init(allocator);
    defer path_stack.deinit();

    const total_accepted = try wf_list.findAcceptableRange(start_range, "in", &path_stack);

    print("\nTotal Accepted: {}\n", .{total_accepted});
}

const PathList = std.ArrayList([]const u8);

const WorkflowList = struct {
    workflows: WorkflowHashMap,
    allocator: std.mem.Allocator,

    const WorkflowHashMap = std.StringHashMap(Workflow);

    pub fn init(allocator: std.mem.Allocator) WorkflowList {
        return .{ .allocator = allocator, .workflows = WorkflowHashMap.init(allocator) };
    }

    pub fn deinit(self: *WorkflowList) void {
        var iter = self.workflows.valueIterator();
        while (iter.next()) |wf| {
            wf.deinit();
        }
        self.workflows.deinit();
    }

    const AcceptableRangeResult = struct {
        accepted: enum { accepted, rejected, unknown },
        range: CategoryRange,
    };

    pub fn findAcceptableRange(self: WorkflowList, range: CategoryRange, target: []const u8, path_list: *PathList) !usize {
        // print("  {s}: x[{:4},{:4}], m[{:4},{:4}], a[{:4},{:4}], s[{:4},{:4}]\n", .{
        //     target,
        //     range.x.min,
        //     range.x.max,
        //     range.m.min,
        //     range.m.max,
        //     range.a.min,
        //     range.a.max,
        //     range.s.min,
        //     range.s.max,
        // });

        // Rejected
        if (std.mem.eql(u8, target, "R")) {
            //print("Rejected\n", .{});
            return 0;
        }

        // Accepted
        if (std.mem.eql(u8, target, "A")) {
            const range_accepted = range.x.rangeAccepted() * range.m.rangeAccepted() * range.a.rangeAccepted() * range.s.rangeAccepted();

            print("Accepted: ", .{});
            for (path_list.items) |path| {
                print("{s} -> ", .{path});
            }
            print("Accepted x[{:4},{:4}]{}, m[{:4},{:4}]{}, a[{:4},{:4}]{}, s[{:4},{:4}]{} {}\n", .{
                range.x.min,
                range.x.max,
                range.x.rangeAccepted(),
                range.m.min,
                range.m.max,
                range.m.rangeAccepted(),
                range.a.min,
                range.a.max,
                range.a.rangeAccepted(),
                range.s.min,
                range.s.max,
                range.s.rangeAccepted(),
                range_accepted,
            });

            return range_accepted;
        }

        // Add target to path list
        try path_list.append(target);

        // Process workflow rules
        var accepted: usize = 0;
        if (self.workflows.get(target)) |wf| {
            var invalid_range = CategoryRange.initFromRange(range);

            for (wf.rules.items) |rule| {
                var valid_range = invalid_range;

                // Apply inverse instruction
                if (rule.instruction) |inst| {
                    switch (inst.cat) {
                        .x => switch (inst.op) {
                            .gt => invalid_range.x = valid_range.x.rangeLessThanEqual(inst.val).?,
                            .lt => invalid_range.x = valid_range.x.rangeGreaterThanEqual(inst.val).?,
                        },
                        .m => switch (inst.op) {
                            .gt => invalid_range.m = valid_range.m.rangeLessThanEqual(inst.val).?,
                            .lt => invalid_range.m = valid_range.m.rangeGreaterThanEqual(inst.val).?,
                        },
                        .a => switch (inst.op) {
                            .gt => invalid_range.a = valid_range.a.rangeLessThanEqual(inst.val).?,
                            .lt => invalid_range.a = valid_range.a.rangeGreaterThanEqual(inst.val).?,
                        },
                        .s => switch (inst.op) {
                            .gt => invalid_range.s = valid_range.s.rangeLessThanEqual(inst.val).?,
                            .lt => invalid_range.s = valid_range.s.rangeGreaterThanEqual(inst.val).?,
                        },
                    }
                }

                // Apply instruction
                if (rule.instruction) |inst| {
                    switch (inst.cat) {
                        .x => switch (inst.op) {
                            .lt => valid_range.x = valid_range.x.rangeLessThan(inst.val) orelse continue,
                            .gt => valid_range.x = valid_range.x.rangeGreaterThan(inst.val) orelse continue,
                        },

                        .m => switch (inst.op) {
                            .lt => valid_range.m = valid_range.m.rangeLessThan(inst.val) orelse continue,
                            .gt => valid_range.m = valid_range.m.rangeGreaterThan(inst.val) orelse continue,
                        },
                        .a => switch (inst.op) {
                            .lt => valid_range.a = valid_range.a.rangeLessThan(inst.val) orelse continue,
                            .gt => valid_range.a = valid_range.a.rangeGreaterThan(inst.val) orelse continue,
                        },
                        .s => switch (inst.op) {
                            .lt => valid_range.s = valid_range.s.rangeLessThan(inst.val) orelse continue,
                            .gt => valid_range.s = valid_range.s.rangeGreaterThan(inst.val) orelse continue,
                        },
                    }
                }

                // Call target rule
                accepted += try self.findAcceptableRange(valid_range, rule.target, path_list);
            }
        }

        _ = path_list.pop();
        return accepted;
    }
};

const CategoryRange = struct {
    x: Range,
    m: Range,
    a: Range,
    s: Range,

    const Range = struct {
        min: usize,
        max: usize,

        // Range a < b
        pub fn countLessThan(a: Range, b: Range) !usize {
            try expect(a.min <= a.max and b.min <= b.max);
            return if (a.min > b.min) return 0 else @min(a.max, b.min) - a.min;
        }

        // Range a > b
        pub fn countGreaterThan(a: Range, b: Range) !usize {
            try expect(a.min <= a.max and b.min <= b.max);
            return if (a.max < b.max) return 0 else a.max - @max(a.min, b.max);
        }

        pub fn rangeLessThan(a: Range, val: usize) ?Range {
            return if (val <= a.min) null else .{ .min = a.min, .max = @min(a.max, @max(a.min, val - 1)) };
        }

        pub fn rangeLessThanEqual(a: Range, val: usize) ?Range {
            return if (val < a.min) null else .{ .min = a.min, .max = @min(a.max, @max(a.min, val)) };
        }

        pub fn rangeGreaterThan(a: Range, val: usize) ?Range {
            return if (val >= a.max) null else .{ .min = @max(a.min, @min(a.max, val + 1)), .max = a.max };
        }

        pub fn rangeGreaterThanEqual(a: Range, val: usize) ?Range {
            return if (val > a.max) null else .{ .min = @max(a.min, @min(a.max, val)), .max = a.max };
        }

        pub fn rangeAccepted(self: Range) usize {
            return (self.max - self.min) + 1;
        }
    };

    pub fn initFromRange(range: CategoryRange) CategoryRange {
        return .{
            .x = .{ .min = range.x.min, .max = range.x.max },
            .m = .{ .min = range.m.min, .max = range.m.max },
            .a = .{ .min = range.a.min, .max = range.a.max },
            .s = .{ .min = range.s.min, .max = range.s.max },
        };
    }
};

const Workflow = struct {
    name: []const u8,
    rules: RuleList,
    allocator: std.mem.Allocator,

    const Category = enum { x, m, a, s };

    const Operation = enum {
        gt,
        lt,

        pub fn compare(op: Operation, a: usize, b: usize) bool {
            return switch (op) {
                .gt => a > b,
                .lt => a < b,
            };
        }
    };

    const RuleInstruction = struct {
        cat: Category,
        op: Operation,
        val: usize,
    };

    const Rule = struct {
        target: []const u8,
        instruction: ?RuleInstruction,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, target: []const u8) !Rule {
            return .{
                .allocator = allocator,
                .instruction = null,
                .target = try allocator.dupe(u8, target),
            };
        }

        pub fn deinit(self: Rule) void {
            self.allocator.free(self.target);
        }

        pub fn setInstruction(self: *Rule, cat: Category, op: Operation, val: usize) void {
            if (self.instruction) |*instruction| {
                instruction.cat = cat;
                instruction.op = op;
                instruction.val = val;
            } else {
                self.instruction = RuleInstruction{ .cat = cat, .op = op, .val = val };
            }
        }
    };
    const RuleList = std.ArrayList(Rule);

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Workflow {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .rules = RuleList.init(allocator),
        };
    }

    pub fn deinit(self: Workflow) void {
        self.allocator.free(self.name);
        for (self.rules.items) |r| {
            r.deinit();
        }
        self.rules.deinit();
    }

    // The returned pointer may be invalidated if the list changes
    pub fn appendRule(self: *Workflow, target: []const u8) !*Rule {
        try self.rules.append(try Rule.init(self.allocator, target));
        return &self.rules.items[self.rules.items.len - 1];
    }
};

test "Workflow allocation" {
    const allocator = std.testing.allocator;

    var wf = try Workflow.init(allocator, "test");
    defer wf.deinit();
}

test "Workflow Rule allocation" {
    const allocator = std.testing.allocator;
    print("\n", .{});

    var wf = try Workflow.init(allocator, "test");
    defer wf.deinit();

    _ = try wf.appendRule("rule test");
}

const PartRating = struct {
    x: ?usize,
    m: ?usize,
    a: ?usize,
    s: ?usize,

    pub fn init() PartRating {
        return .{ .x = null, .m = null, .a = null, .s = null };
    }
};

test "Range operators" {
    const a = CategoryRange.Range{ .min = 3, .max = 9 };
    const b1 = CategoryRange.Range{ .min = 2, .max = 10 };
    const b2 = CategoryRange.Range{ .min = 5, .max = 12 };
    const b3 = CategoryRange.Range{ .min = 1, .max = 5 };
    const b4 = CategoryRange.Range{ .min = 6, .max = 7 };

    try expect(try a.countGreaterThan(a) == 0);
    try expect(try a.countGreaterThan(b1) == 0);
    try expect(try a.countGreaterThan(b2) == 0);
    try expect(try a.countGreaterThan(b3) == 4);
    try expect(try a.countGreaterThan(b4) == 2);

    try expect(try a.countLessThan(a) == 0);
    try expect(try a.countLessThan(b1) == 0);
    try expect(try a.countLessThan(b2) == 2);
    try expect(try a.countLessThan(b3) == 0);
    try expect(try a.countLessThan(b4) == 3);
}

test "Range Accepted" {
    const a = CategoryRange.Range{ .min = 1, .max = 10 };
    print("\n    a: [{},{}] {}\n", .{ a.min, a.max, a.rangeAccepted() });
    try expect(a.rangeAccepted() == 10);

    const a_lt = a.rangeLessThan(5).?;
    print("a < 5: [{},{}] {}\n", .{ a_lt.min, a_lt.max, a_lt.rangeAccepted() });
    try expect(a_lt.rangeAccepted() == 4);

    const a_gt = a.rangeGreaterThan(5).?;
    print("a > 5: [{},{}] {}\n", .{ a_gt.min, a_gt.max, a_gt.rangeAccepted() });
    try expect(a_gt.rangeAccepted() == 5);

    const a_lte = a.rangeLessThanEqual(5).?;
    print("a ≤ 5: [{},{}] {}\n", .{ a_lte.min, a_lte.max, a_lte.rangeAccepted() });
    try expect(a_lte.rangeAccepted() == 5);

    const a_gte = a.rangeGreaterThanEqual(5).?;
    print("a ≥ 5: [{},{}] {}\n", .{ a_gte.min, a_gte.max, a_gte.rangeAccepted() });
    try expect(a_gte.rangeAccepted() == 6);

    const a_lt_gt = a.rangeGreaterThan(3).?.rangeLessThan(7).?;
    print("3<a<7: [{},{}] {}\n", .{ a_lt_gt.min, a_lt_gt.max, a_lt_gt.rangeAccepted() });
    try expect(a_lt_gt.rangeAccepted() == 3);

    const a_lt_gte = a.rangeGreaterThanEqual(3).?.rangeLessThan(7).?;
    print("3≤a<7: [{},{}] {}\n", .{ a_lt_gte.min, a_lt_gte.max, a_lt_gte.rangeAccepted() });
    try expect(a_lt_gte.rangeAccepted() == 4);

    const a_lte_gte = a.rangeGreaterThanEqual(3).?.rangeLessThanEqual(7).?;
    print("3≤a≤7: [{},{}] {}\n", .{ a_lte_gte.min, a_lte_gte.max, a_lte_gte.rangeAccepted() });
    try expect(a_lte_gte.rangeAccepted() == 5);

    const a_lt_1 = a.rangeLessThan(1);
    print("a < 1: {?}\n", .{a_lt_1});
    try expect(a_lt_1 == null);

    const a_lte_1 = a.rangeLessThanEqual(1).?;
    print("a ≤ 1: [{},{}] {}\n", .{ a_lte_1.min, a_lte_1.max, a_lte_1.rangeAccepted() });
    try expect(a_lte_1.rangeAccepted() == 1);

    const a_gt_10 = a.rangeGreaterThan(10);
    print("a > 10: {?}\n", .{a_gt_10});
    try expect(a_gt_10 == null);

    const a_gte_10 = a.rangeGreaterThanEqual(10).?;
    print("a ≥ 10: [{},{}] {}\n", .{ a_gte_10.min, a_gte_10.max, a_gte_10.rangeAccepted() });
    try expect(a_gte_10.rangeAccepted() == 1);
}
