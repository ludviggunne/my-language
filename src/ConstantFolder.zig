
const std = @import("std");
const Ast = @import("Ast.zig");
const SymbolTable = @import("SymbolTable.zig");
const Error = @import("Error.zig");
const Self = @This();

ast:       *Ast,
symtab:    *SymbolTable,
errors:    std.ArrayList(Error),
top_level: bool,

pub fn init(ast: *Ast, symtab: *SymbolTable, allocator: std.mem.Allocator) Self {

    return .{
        .ast = ast,
        .symtab = symtab,
        .errors = std.ArrayList(Error).init(allocator),
        .top_level = true,
    };
}

pub fn deinit(self: *Self) void {

    self.errors.deinit();
}

pub fn fold(self: *Self) !void {

    try self.foldNode(self.ast.root);
    if (self.errors.items.len > 0) {
        return error.ConstantError;
    }
}

fn getConstOrNull(self: *Self, node: usize) ?i64 {

    return switch (self.ast.nodes.items[node]) {
        .constant => |v| v.value,
        else => null,
    };
}

fn pushError(self: *Self, err: Error) !void {

    try self.errors.append(err);
}

fn foldNode(self: *Self, id: usize) !void {

    var node = &self.ast.nodes.items[id];

    switch (node.*) {

        .empty,
        .break_statement,
        .continue_statement,
        .parameter_list => {},
        .variable => |v| {
            if (self.top_level) {
                const symbol = &self.symtab.symbols.items[v.symbol];
                switch (symbol.kind.variable) {
                    .global => |w| {
                        node.* = .{ .constant = .{ .type_ = symbol.type_, .value = w } };
                    },
                    else => {},
                }
            }
        },

        .parenthesized => |v| try self.foldNode(v.content),

        // TOPLEVEL
        .toplevel_list => |v| {
            self.top_level = true;
            try self.foldNode(v.decl);
            if (v.next) |next| {
                self.top_level = true;
                try self.foldNode(next);
            }
        },

        // FUNCTION
        .function => |v| {
            try self.foldNode(v.body);
        },

        // BLOCK
        .block => |v| {
            self.top_level = false;
            try self.foldNode(v.content);
        },

        // STATEMENT LIST
        .statement_list => |v| {
            try self.foldNode(v.statement);
            if (v.next) |next| {
                try self.foldNode(next);
            }
        },

        // DECLARATION
        .declaration => |v| {
            try self.foldNode(v.expr);
            switch (self.symtab.symbols.items[v.symbol].kind.variable) {
                .global => |*w| {
                    // insert nonsense value if not evaluated since
                    // compilation will terminate anyway
                    w.* = self.getConstOrNull(v.expr) orelse 0xaa;
                },
                else => {},
            }
        },

        // ASSIGNMENT
        .assignment => |v| {
            try self.foldNode(v.expr);
        },

        // IF
        .if_statement => |*v| {
            try self.foldNode(v.condition);
            try self.foldNode(v.block);
            if (v.else_block) |else_block| {
                try self.foldNode(else_block);
            }
            if (self.getConstOrNull(v.condition)) |condition| {
                if (condition == 1) {
                    node.* = self.ast.nodes.items[v.block];
                } else {
                    if (v.else_block) |else_block| {
                        node.* = self.ast.nodes.items[else_block];
                    } else {
                        node.* = .empty;
                    }
                }
            }
        },

        // WHILE
        .while_statement => |v| {
            try self.foldNode(v.condition);
            try self.foldNode(v.block);
        },

        // RETURN
        .return_statement => |v| {
            try self.foldNode(v.expr);
        },

        // PRINT
        .print_statement => |v| {
            try self.foldNode(v.expr);
        },

        // CALL
        .call => |v| {
            if (self.top_level) {
                try self.pushError(.{
                    .stage = .constant_folding,
                    .where = v.name.where,
                    .kind = .call_in_toplevel,
                });
            }
            if (v.args) |args| {
                try self.foldNode(args);
            }
        },

        // ARGUMENTS
        .argument_list => |v| {
            try self.foldNode(v.expr);
            if (v.next) |next| {
                try self.foldNode(next);
            }
        },

        // CONSTANT
        .constant => |*v| switch (v.token.?.kind) {
            .literal => v.value = std.fmt.parseInt(i64, v.token.?.where, 10)
                catch unreachable, // string is validated during lexing
            .@"true" => v.value = 1,
            .@"false" => v.value = 0,
            else => unreachable,
        },

        // UNARY
        .unary => |*v| {

            try self.foldNode(v.operand);

            if (self.getConstOrNull(v.operand)) |operand| {

                const value = switch (v.operator.kind) {
                    .@"-" => -operand,
                    .@"!" => operand ^ @as(i64, 1),
                    else => unreachable, // illegal unary operator
                };

                node.* = .{ .constant = .{ .type_ = undefined, .value = value } };
            }
        },

        // BINARY
        .binary => |*v| {

            try self.foldNode(v.left);
            try self.foldNode(v.right);

            if (self.getConstOrNull(v.left)) |left| {
                if (self.getConstOrNull(v.right)) |right| {

                    const value = switch (v.operator.kind) {
                        .@"+" => left + right,
                        .@"-" => left - right,
                        .@"*" => left * right,
                        .@"/" => div: {
                            if (right == 0) {
                                try self.pushError(.{
                                    .stage = .constant_folding,
                                    .where = v.operator.where,
                                    .kind = .division_by_zero,
                                });
                                return;
                            }
                            // TODO: Look in to this
                            break :div @divTrunc(left, right);
                        },
                        .@"%" => mod: {
                            if (right == 0) {
                                try self.pushError(.{
                                    .stage = .constant_folding,
                                    .where = v.operator.where,
                                    .kind = .division_by_zero,
                                });
                                return;
                            }
                            break :mod @mod(left, right);
                        },
                        .@"and" => left & right,
                        .@"or"  => left | right,
                        else => comparison: {
                            const as_bool = switch (v.operator.kind) {
                                .@"<"  => left <  right,
                                .@"<=" => left <= right,
                                .@"==" => left == right,
                                .@">=" => left >= right,
                                .@">"  => left >  right,
                                .@"!=" => left != right,
                                else => unreachable, // illegal binary operator
                            };
                            break :comparison @as(i64, @intFromBool(as_bool));
                        },
                    };

                    node.* = .{ .constant = .{ .type_ = undefined, .value = value, }, };
                }
            }
        },
    }
}
