
const std = @import("std");
const Self = @This();
const Token = @import("Token.zig");

root: usize,
nodes: std.ArrayList(Node),

const Node = union(enum) {

    empty,
    break_statement,
    continue_statement,

    toplevel_list: struct {
        decl: usize,
        next: ?usize,
    },

    function: struct {
        symbol: usize = undefined,
        name:   Token,
        params: ?usize, // may be empty
        body:   usize,
    },

    parameter_list: struct {
        symbol: usize = undefined,
        name:   Token,
        next:   ?usize,
    },
    
    declaration: struct {
        symbol: usize = undefined,
        name:   Token,
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
        condition:  usize,
        block:      usize,
        else_block: ?usize,
    },

    while_statement: struct {
        condition: usize,
        block:     usize,
    },

    return_statement: struct {
        expr: ?usize,
    },

    print_statement: struct {
        expr: usize,
    },

    variable: struct {
        symbol: usize = undefined,
        name:   Token,
    },

    constant: struct {
        value: i32 = 0,
        token: Token,
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

pub fn dump(self: *Self, writer: anytype) !void{

    try self.dumpNode(self.root, writer, 0);
}

fn dumpNode(self: *Self, id: usize, writer: anytype, i: usize) !void {

    if (i > 0) {
        for (0..i - 1) |_| {
            try writer.print("|   ", .{});
        }
        try writer.print("*---", .{});
    }

    const node = &self.nodes.items[id];
    switch (node.*) {

        .empty => try writer.print("empty\n", .{}),

        .toplevel_list => |v| {
            try writer.print("toplevel-list\n", .{});
            try self.dumpNode(v.decl, writer, i + 1);
            if (v.next) |next| {
                try self.dumpNode(next, writer, i + 1);
            }
        },

        .function => |v| {
            try writer.print("function \"{s}\"\n", .{ v.name.where, });
            if (v.params) |params| {
                try self.dumpNode(params, writer, i + 1);
            }
            try self.dumpNode(v.body, writer, i + 1);
        },

        .parameter_list => |v| {
            try writer.print("param \"{s}\"\n", .{ v.name.where, });
            if (v.next) |next| {
                try self.dumpNode(next, writer, i + 1);
            }
        },

        .block => |v| {
            try writer.print("block\n", .{});
            try self.dumpNode(v.content, writer, i + 1);
        },

        .statement_list => |v| {
            try writer.print("statement-list\n", .{});
            try self.dumpNode(v.statement, writer, i + 1);
            if (v.next) |next| {
                try self.dumpNode(next, writer, i + 1);
            }
        },

        .declaration => |v| {
            try writer.print("declaration \"{s}\"\n", .{ v.name.where, });
            try self.dumpNode(v.expr, writer, i + 1);
        },

        .assignment => |v| {
            try writer.print(
                "assignment \"{s}\" ({s})\n",
                .{ v.name.where, @tagName(v.operator.kind), }
            );
            try self.dumpNode(v.expr, writer, i + 1);
        },

        .binary => |v| {
            try writer.print("binary ({s})\n", .{ @tagName(v.operator.kind), });
            try self.dumpNode(v.left, writer, i + 1);
            try self.dumpNode(v.right, writer, i + 1);
        },

        .unary => |v| {
            try writer.print("unary ({s})\n", .{ @tagName(v.operator.kind), });
            try self.dumpNode(v.operand, writer, i + 1);
        },

        .call => |v| {
            try writer.print("call \"{s}\"\n", .{ v.name.where, });
            if (v.args) |args| {
                try self.dumpNode(args, writer, i + 1);
            }
        },

        .argument_list => |v| {
            try writer.print("arg\n", .{});
            try self.dumpNode(v.expr, writer, i + 1);
            if (v.next) |next| {
                try self.dumpNode(next, writer, i + 1);
            }
        },

        .break_statement => try writer.print("break\n", .{}),

        .continue_statement => try writer.print("continue\n", .{}),

        .return_statement => |v| {
            try writer.print("return\n", .{});
            if (v.expr) |expr| {
                try self.dumpNode(expr, writer, i + 1);
            }
        }, 

        .print_statement => |v| {
            try writer.print("print\n", .{});
            try self.dumpNode(v.expr, writer, i + 1);
        }, 

        .if_statement => |v| {
            const str = if (v.else_block) |_| "if-else\n" else "if\n";
            try writer.print("{s}", .{ str, });
            try self.dumpNode(v.condition, writer, i + 1);
            try self.dumpNode(v.block, writer, i + 1);
            if (v.else_block) |else_block| {
                try self.dumpNode(else_block, writer, i + 1);
            }
        },

        .while_statement => |v| {
            try writer.print("while\n", .{});
            try self.dumpNode(v.condition, writer, i + 1);
            try self.dumpNode(v.block, writer, i + 1);
        },

        .variable => |v| {
            try writer.print("variable \"{s}\"\n", .{ v.name.where, });
        },

        .constant => |v| {
            try writer.print("constant ({s})\n", .{ v.token.where, });
        },
    }
}
