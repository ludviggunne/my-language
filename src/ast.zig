
const std = @import("std");

pub const Token = @import("token.zig").Token;

pub const Node = union(enum) {

    statement_list: struct {
        first: usize,
        follow: usize,
    },

    declaration: struct {
        identifier: Token,
        expression: usize,
    },

    assignment: struct {
        identifier: Token,
        operator:   Token,
        expression: usize,
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
        token: Token,
    },
};

pub fn print(ast: []Node, root: usize) void {
    
    var indent: usize = 0;    
    print_(ast, root, &indent);
}

fn print_(ast: []Node, root: usize, indent: *usize) void {
    
    indent.* += 1;
    defer indent.* -= 1;

    for (0..indent.*) |_| std.debug.print("    ", .{});

    switch (ast[root]) {

        .atomic => |a| std.debug.print(
            "ATOMIC: {s} -> {s}\n",
            .{
                @tagName(a.token.kind),
                a.token.loc,
            }
        ),

        .statement_list => |l| {
            std.debug.print("STATEMENT LIST:\n", .{});
            print_(ast, l.first, indent);
            print_(ast, l.follow, indent);
        },

        .declaration => |d| {
            std.debug.print("DECLARATION: {s}\n", .{ d.identifier.loc });
            print_(ast, d.expression, indent);
        },

        .binary => |b| {
            std.debug.print("BINARY: {s}\n", .{ b.operator.loc });
            print_(ast, b.left, indent);
            print_(ast, b.right, indent);
        },

        .assignment => |a| {
            std.debug.print("ASSIGNMENT: {s} {s}\n", .{ a.identifier.loc, @tagName(a.operator.kind), });
            print_(ast, a.expression, indent);
        },

        .unary => |u| {
            std.debug.print("UNARY: {s}\n", .{ u.operator.loc, });
            print_(ast, u.operand, indent);
        },
    }
}
