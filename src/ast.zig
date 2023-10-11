
// TODO: Refactor as "file struct"

const std = @import("std");

pub const Token = @import("Token.zig");

pub const Ast = struct {

    root: usize,
    nodes: []Node,
};

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

    atomic: struct {
        symbol: usize = 0,
        literal: ?[]const u8 = null,
        token: Token,
    },
};

pub fn print(source: []const u8, ast: *const Ast) void {
    
    var indent: usize = 0;    
    print_(source, ast.nodes, ast.root, &indent);
}

fn print_(source: []const u8, ast: []const Node, root: usize, indent: *usize) void {
    
    indent.* += 1;
    defer indent.* -= 1;

    for (0..indent.*) |_| std.debug.print("    ", .{});

    switch (ast[root]) {

        .atomic => |a| std.debug.print(
            "ATOMIC: {s} -> {s}\n",
            .{
                @tagName(a.token.kind),
                source[a.token.begin..a.token.end],
            }
        ),

        .block => |b| {
            std.debug.print("BLOCK:\n", .{});
            print_(source, ast, b.content, indent);
        },

        .if_statement => |i| {
            std.debug.print("IF STATEMENT:\n", .{});
            print_(source, ast, i.condition, indent);
            print_(source, ast, i.block, indent);
        },

        .while_statement => |w| {
            std.debug.print("WHILE STATEMENT:\n", .{});
            print_(source, ast, w.condition, indent);
            print_(source, ast, w.block, indent);
        },

        .statement_list => |l| {
            std.debug.print("STATEMENT LIST:\n", .{});
            print_(source, ast, l.first, indent);
            print_(source, ast, l.follow, indent);
        },

        .declaration => |d| {
            std.debug.print("DECLARATION: {s}\n", .{ source[d.identifier.begin..d.identifier.end] });
            print_(source, ast, d.expression, indent);
        },

        .binary => |b| {
            std.debug.print("BINARY: {s}\n", .{ @tagName(b.operator.kind) });
            print_(source, ast, b.left, indent);
            print_(source, ast, b.right, indent);
        },

        .assignment => |a| {
            std.debug.print("ASSIGNMENT: {s} {s}\n", .{
                source[a.identifier.begin..a.identifier.end],
                @tagName(a.operator.kind)
            });
            print_(source, ast, a.expression, indent);
        },

        .unary => |u| {
            std.debug.print("UNARY: {s}\n", .{ @tagName(u.operator.kind), });
            print_(source, ast, u.operand, indent);
        },

        .print_statement => |p| {
            std.debug.print("PRINT:\n", .{});
            print_(source, ast, p.argument, indent);
        },

        .empty => std.debug.print("EMPTY\n", .{}),
    }
}
