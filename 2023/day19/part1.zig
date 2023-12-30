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
        print("{}: ", .{i});

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
                rule.*.cat = switch (op[0]) {
                    'x' => .x,
                    'm' => .m,
                    'a' => .a,
                    's' => .s,
                    else => undefined,
                };
                rule.*.op = switch (op[1]) {
                    '>' => .gt,
                    '<' => .lt,
                    else => undefined,
                };
                rule.*.val = try std.fmt.parseInt(usize, op[2..], 10);
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
        print("{s} | ", .{wf.name});
        for (wf.rules.items) |r| {
            if (r.cat) |cat| print("{s} ", .{@tagName(cat)});
            if (r.op) |op| print("{s} ", .{@tagName(op)});
            if (r.val) |val| print("{} : ", .{val});

            print("{s}, ", .{r.target});
        }
        print("\n", .{});
    }

    i = 0;
    print("\n", .{});
    // Process parts list
    var total_rating: usize = 0;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var toks = std.mem.tokenizeAny(u8, line, "{},");
        print("{}: ", .{i});

        var pr = PartRating.init();

        while (toks.next()) |t| {
            print("{s} {s} ", .{ t[0..2], t[2..] });

            switch (t[0]) {
                'x' => pr.x = try std.fmt.parseInt(usize, t[2..], 10),
                'm' => pr.m = try std.fmt.parseInt(usize, t[2..], 10),
                'a' => pr.a = try std.fmt.parseInt(usize, t[2..], 10),
                's' => pr.s = try std.fmt.parseInt(usize, t[2..], 10),
                else => undefined,
            }
        }

        const part_rating = try wf_list.processPart(pr);
        print("Rating: {}", .{part_rating});

        total_rating += part_rating;

        i += 1;
        print("\n", .{});
    }

    print("\nTotal Rating: {}\n", .{total_rating});
}

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

    pub fn processPart(self: WorkflowList, part: PartRating) !usize {
        var wf = self.workflows.get("in") orelse return error.WorkflowNotFound;

        while (true) {
            for (wf.rules.items) |rule| {
                var rule_valid: bool = true;

                if (rule.cat != null and rule.op != null and rule.val != null) {
                    rule_valid = switch (rule.cat.?) {
                        .x => rule.op.?.compare(part.x.?, rule.val.?),
                        .m => rule.op.?.compare(part.m.?, rule.val.?),
                        .a => rule.op.?.compare(part.a.?, rule.val.?),
                        .s => rule.op.?.compare(part.s.?, rule.val.?),
                    };
                }

                if (rule_valid) {
                    // Accept
                    if (std.mem.eql(u8, rule.target, "A")) {
                        return part.x.? + part.m.? + part.a.? + part.s.?;
                    }
                    // Reject
                    if (std.mem.eql(u8, rule.target, "R")) {
                        return 0;
                    }
                    // Get next rule
                    wf = self.workflows.get(rule.target) orelse return error.WorkflowNotFound;
                    break;
                }
            }
        }

        return 0;
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

    const Rule = struct {
        cat: ?Category,
        op: ?Operation,
        val: ?usize,
        target: []const u8,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, target: []const u8) !Rule {
            return .{
                .allocator = allocator,
                .cat = null,
                .op = null,
                .val = null,
                .target = try allocator.dupe(u8, target),
            };
        }

        pub fn deinit(self: Rule) void {
            self.allocator.free(self.target);
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
