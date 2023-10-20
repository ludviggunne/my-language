
const Self = @This();

const std = @import("std");

const Ast = @import("Ast.zig");
const Token = @import("Token.zig");
const precedence = @import("precedence.zig");

const Stage = enum { pre, flip, post, };

ast:             *Ast,
atomic_stack:    std.ArrayList(Token),
operator_stacks: [precedence.count] std.ArrayList(Token),

pub fn init(ast: *Ast, allocator: std.mem.Allocator) Self {

    var self: Self = .{
        .ast = ast,
        .atomic_stack = std.ArrayList(Token).init(allocator),
        .operator_stacks = undefined,
    };

    for (&self.operator_stacks) |*stack| {
        stack.* = std.ArrayList(Token).init(allocator);
    }

    return self;
}

pub fn deinit(self: *Self) void {

    self.atomic_stack.deinit();
    for (&self.operator_stacks) |*stack| {
        stack.deinit();
    }
}

pub fn fix(self: *Self) !void {
    _ = self;
}

pub fn fixNode(self: *Self, id: usize) !void {

    const node = &self.ast.nodes.items[id];

    switch (node.*) {

        .empty => {},

        .break_statement => {},

        .continue_statement => {},

        .toplevel_list => |v| {
            try self.fixNode(v.decl);
            if (v.next) |next| try self.fixNode(next);
        },

        .function => |v| try self.fixNode(v.body),

        .parameter_list => {},

        .declaration => |v| try self.fixExpression(v.expr),

        .assignment => |v| try self.fixExpression(v.expr),

        .block => |v| try self.fixNode(v.content),

        .statement_list => |v| {
            try self.fixNode(v.statement);
            if (v.next) |next| try self.fixNode(next);
        },

        .if_statement => |v| {
            try self.fixExpression(v.condition);
            try self.fixNode(v.block);
            if (v.else_block) |block| try self.fixNode(block);
        },

        .while_statement => |v| {
            try self.fixExpression(v.condition);
            try self.fixNode(v.block);
        },

        .return_statement => |v| try self.fixExpression(v.expr),

        .print_statement => |v| try self.fixExpression(v.expr),

        else => unreachable, // tried to fix expression node as non-expression
    }
}

fn fixExpression(self: *Self, id: usize) !void {

    try self.pre(id);
    try self.flip(id);
    try self.post(id);
}

fn pre(self: *Self, id: usize) !void {

    const node = &self.ast.nodes.items[id];

    switch (node.*) {

        .binary => |v| {
            try self.pre(v.left);
            try self.pre(v.right);
            const prec = precedence.of(v.operator);
            self.operator_stacks[prec].append(v.operator);
        },

        .unary => |v| {
            try self.pre(v.operand);
            self.operator_stacks[prec].append(v.operator);
        }

        .call => |v| if (v.args) |args| try self.pre(args),

        .argument_list => |v| {
            try self.fixExpression(v.expr);
            if (v.next) |next| try self.pre(next);
        },

        .
    }
}
