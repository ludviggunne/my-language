
const std = @import("std");
const Self = @This();
const Token = @import("Token.zig");
const Type = @import("types.zig").Type;

root: usize,
nodes: std.ArrayList(Node),

pub const Node = union(enum) {

    empty,
    break_statement: []const u8,
    continue_statement: []const u8,

    toplevel_list: struct {
        decl: usize,
        next: ?usize,
    },

    function: struct {
        symbol:      usize = undefined,
        name:        Token,
        return_type: Type,
        params:      ?usize, // may be empty
        body:        usize,
    },

    parameter_list: struct {
        symbol: usize = undefined,
        name:   Token,
        type_:  Type,
        next:   ?usize,
    },
    
    declaration: struct {
        symbol: usize = undefined,
        name:   Token,
        type_:   Type,
        expr:   usize,
    }, 

    assignment: struct {
        symbol:   usize = undefined,
        name:     Token,
        operator: Token,
        expr:     usize,
    },

    binary: struct {
        left:     usize,
        right:    usize,
        operator: Token,
    },

    unary: struct {
        operator: Token,
        operand:  usize,
    },
    
    call: struct {
        symbol: usize = undefined,
        name: Token,
        args: ?usize,
    },

    argument_list: struct {
        delimiter: Token,
        expr: usize,
        next: ?usize,
    },

    block: struct {
        content: usize,
    },

    statement_list: struct {
        statement: usize,
        next:      ?usize,
    },

    if_statement: struct {
        keyword:    Token,
        condition:  usize,
        block:      usize,
        else_block: ?usize,
    },

    while_statement: struct {
        keyword:   Token,
        condition: usize,
        block:     usize,
    },

    return_statement: struct {
        keyword: Token,
        expr:    ?usize,
    },

    print_statement: struct {
        expr: usize,
    },

    variable: struct {
        symbol: usize = undefined,
        name:   Token,
    },

    constant: struct {
        value: i64 = 0,
        type_: Type,
        token: ?Token = null, // may not exist after constant folding
    },
};

pub fn init(allocator: std.mem.Allocator) Self {

    return .{
        .root = 0,
        .nodes = std.ArrayList(Node).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.nodes.deinit();
}

pub fn push(self: *Self, node: Node) !usize {

    try self.nodes.append(node);
    return self.nodes.items.len - 1;
}

pub fn dump(self: *Self, writer: anytype, allocator: std.mem.Allocator) !void{

    try writer.print("---------- AST Dump ----------\n", .{});
    var bars = std.ArrayList(bool).init(allocator);
    defer bars.deinit();
    try self.dumpNode(self.root, writer, 0, &bars);
}

fn dumpNode(
    self: *Self,
    id: usize,
    writer: anytype,
    i: usize,
    bars: *std.ArrayList(bool)
) !void {

    if (i > 0) {
        for (0..i - 1) |j| {
            if (bars.items[j]) {
                try writer.print("|   ", .{});
            } else {
                try writer.print("    ", .{});
            }
        }
        try writer.print("*---", .{});
    }

    try setBar(bars, i);
    defer unsetBar(bars, i);

    const node = &self.nodes.items[id];
    switch (node.*) {

        .empty => try writer.print("empty\n", .{}),

        .toplevel_list => |v| {
            try writer.print("toplevel-list\n", .{});
            try spacing(writer, i + 1, bars);
            if (v.next == null) unsetBar(bars, i);
            try self.dumpNode(v.decl, writer, i + 1, bars);
            if (v.next) |next| {
                unsetBar(bars, i);
                try self.dumpNode(next, writer, i + 1, bars);
            }
        },

        .function => |v| {
            try writer.print("function \"{s}\"\n", .{ v.name.where, });
            try spacing(writer, i + 1, bars);
            if (v.params) |params| {
                try self.dumpNode(params, writer, i + 1, bars);
            }
            unsetBar(bars, i);
            try self.dumpNode(v.body, writer, i + 1, bars);
        },

        .parameter_list => |v| {
            try writer.print("param \"{s}\"\n", .{ v.name.where, });
            if (v.next == null) unsetBar(bars, i);
            try spacing(writer, i + 1, bars);
            if (v.next) |next| {
                unsetBar(bars, i);
                try self.dumpNode(next, writer, i + 1, bars);
            }
        },

        .block => |v| {
            try writer.print("block\n", .{});
            try spacing(writer, i + 1, bars);
            unsetBar(bars, i);
            try self.dumpNode(v.content, writer, i + 1, bars);
        },

        .statement_list => |v| {
            try writer.print("statement-list\n", .{});
            try spacing(writer, i + 1, bars);
            if (v.next == null) unsetBar(bars, i);
            try self.dumpNode(v.statement, writer, i + 1, bars);
            if (v.next) |next| {
                unsetBar(bars, i);
                try self.dumpNode(next, writer, i + 1, bars);
            }
        },

        .declaration => |v| {
            try writer.print("declaration \"{s}\"\n", .{ v.name.where, });
            try spacing(writer, i + 1, bars);
            unsetBar(bars, i);
            try self.dumpNode(v.expr, writer, i + 1, bars);
        },

        .assignment => |v| {
            try writer.print(
                "assignment \"{s}\" ({s})\n",
                .{ v.name.where, @tagName(v.operator.kind), }
            );
            try spacing(writer, i + 1, bars);
            unsetBar(bars, i);
            try self.dumpNode(v.expr, writer, i + 1, bars);
        },

        .binary => |v| {
            try writer.print("binary ({s})\n", .{ @tagName(v.operator.kind), });
            try spacing(writer, i + 1, bars);
            try self.dumpNode(v.left, writer, i + 1, bars);
            unsetBar(bars, i);
            try self.dumpNode(v.right, writer, i + 1, bars);
        },

        .unary => |v| {
            try writer.print("unary ({s})\n", .{ @tagName(v.operator.kind), });
            try spacing(writer, i + 1, bars);
            unsetBar(bars, i);
            try self.dumpNode(v.operand, writer, i + 1, bars);
        },

        .call => |v| {
            try writer.print("call \"{s}\"\n", .{ v.name.where, });
            try spacing(writer, i + 1, bars);
            unsetBar(bars, i);
            if (v.args) |args| {
                try self.dumpNode(args, writer, i + 1, bars);
            }
        },

        .argument_list => |v| {
            try writer.print("arg\n", .{});
            try spacing(writer, i + 1, bars);
            if (v.next == null) unsetBar(bars, i);
            try self.dumpNode(v.expr, writer, i + 1, bars);
            if (v.next) |next| {
            unsetBar(bars, i);
                try self.dumpNode(next, writer, i + 1, bars);
            }
        },

        .break_statement => {
            unsetBar(bars, i);
            try writer.print("break\n", .{});
        },

        .continue_statement => {
            unsetBar(bars, i);
            try writer.print("continue\n", .{});
        },

        .return_statement => |v| {
            try writer.print("return\n", .{});
            try spacing(writer, i + 1, bars);
            unsetBar(bars, i);
            if (v.expr) |expr| {
                try self.dumpNode(expr, writer, i + 1, bars);
            }
        }, 

        .print_statement => |v| {
            try writer.print("print\n", .{});
            try spacing(writer, i + 1, bars);
            unsetBar(bars, i);
            try self.dumpNode(v.expr, writer, i + 1, bars);
        }, 

        .if_statement => |v| {
            const str = if (v.else_block) |_| "if-else\n" else "if\n";
            try writer.print("{s}", .{ str, });
            try spacing(writer, i + 1, bars);
            try self.dumpNode(v.condition, writer, i + 1, bars);
            try self.dumpNode(v.block, writer, i + 1, bars);
            unsetBar(bars, i);
            if (v.else_block) |else_block| {
                try self.dumpNode(else_block, writer, i + 1, bars);
            }
        },

        .while_statement => |v| {
            try writer.print("while\n", .{});
            try spacing(writer, i + 1, bars);
            try self.dumpNode(v.condition, writer, i + 1, bars);
            unsetBar(bars, i);
            try self.dumpNode(v.block, writer, i + 1, bars);
        },

        .variable => |v| {
            try writer.print("variable \"{s}\"\n", .{ v.name.where, });
        },

        .constant => |v| {
            // Pick field depending on wether we've done constant folding or not
            if (v.token) |token| {
                try writer.print("constant ({s})\n", .{ token.where, });
            } else {
                try writer.print("constant ({d})\n", .{ v.value, });
            }
        },
    }

}

fn spacing(writer: anytype, i: usize, bars: *std.ArrayList(bool)) !void {

    if (i > 0) {
        for (0..i - 1) |j| {
            if (bars.items[j]) {
                try writer.print("|   ", .{});
            } else {
                try writer.print("    ", .{});
            }
        }
        try writer.print("|\n", .{});
    }
}

fn setBar(bars: *std.ArrayList(bool), at: usize) !void {
    
    while (at >= bars.items.len) {
        try bars.append(false); 
    }

    bars.items[at] = true;
}

fn unsetBar(bars: *std.ArrayList(bool), at: usize) void {
    
    bars.items[at] = false;
}
