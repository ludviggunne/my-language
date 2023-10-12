
const std = @import("std");

const Self = @This();
const Token = @import("Token.zig");

root: usize,
nodes: []Node,

pub const Node = union(enum) {

    statement_list: struct {
        first: usize,
        follow: usize,
    },

    empty,

    block: struct {
        content: usize,
    },

    declaration: struct {
        symbol:     usize = 0,
        identifier: Token,
        expression: usize,
    },

    assignment: struct {
        symbol:     usize = 0,
        identifier: Token,
        operator:   Token,
        expression: usize,
    },

    print_statement: struct {
        argument: usize,
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
    
    unary: struct {
        operator: Token,
        operand:  usize,
    },

    binary: struct {
        left:     usize,
        operator: Token,
        right:    usize,
    },

    break_statement,

    atomic: struct {
        symbol: usize = 0,
        literal: ?[]const u8 = null,
        token: Token,
    },
};

pub fn print(self: *Self, source: []const u8) void {
    
    var indent: usize = 0;    
    self.print_(source, self.root, &indent);
}

fn print_(self: *Self, source: []const u8, root: usize, indent: *usize) void {
    
    indent.* += 1;
    defer indent.* -= 1;

    for (0..indent.*) |_| std.debug.print("    ", .{});

    switch (self.nodes[root]) {

        .atomic => |a| std.debug.print(
            "ATOMIC: {s} -> {s}\n",
            .{
                @tagName(a.token.kind),
                source[a.token.begin..a.token.end],
            }
        ),

        .block => |b| {
            std.debug.print("BLOCK:\n", .{});
            self.print_(source, b.content, indent);
        },

        .if_statement => |i| {
            std.debug.print("IF STATEMENT:\n", .{});
            self.print_(source, i.condition, indent);
            self.print_(source, i.block, indent);
        },

        .while_statement => |w| {
            std.debug.print("WHILE STATEMENT:\n", .{});
            self.print_(source, w.condition, indent);
            self.print_(source, w.block, indent);
        },

        .statement_list => |l| {
            std.debug.print("STATEMENT LIST:\n", .{});
            self.print_(source, l.first, indent);
            self.print_(source, l.follow, indent);
        },

        .declaration => |d| {
            std.debug.print("DECLARATION: {s}\n", .{ source[d.identifier.begin..d.identifier.end] });
            self.print_(source, d.expression, indent);
        },

        .binary => |b| {
            std.debug.print("BINARY: {s}\n", .{ @tagName(b.operator.kind) });
            self.print_(source, b.left, indent);
            self.print_(source, b.right, indent);
        },

        .assignment => |a| {
            std.debug.print("ASSIGNMENT: {s} {s}\n", .{
                source[a.identifier.begin..a.identifier.end],
                @tagName(a.operator.kind)
            });
            self.print_(source, a.expression, indent);
        },

        .unary => |u| {
            std.debug.print("UNARY: {s}\n", .{ @tagName(u.operator.kind), });
            self.print_(source, u.operand, indent);
        },

        .print_statement => |p| {
            std.debug.print("PRINT:\n", .{});
            self.print_(source, p.argument, indent);
        },

        .empty => std.debug.print("EMPTY\n", .{}),

        .break_statment => std.debug.print("BREAK\n", .{}),
    }
}
