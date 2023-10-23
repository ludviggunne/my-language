
const std         = @import("std");
const Self        = @This();
const Ast         = @import("Ast.zig");
const Error       = @import("Error.zig");
const SymbolTable = @import("SymbolTable.zig");
const Type        = @import("types.zig").Type;

ast: *Ast,
symtab: *SymbolTable,
errors: std.ArrayList(Error),
return_type: Type,
param_index: usize,

pub fn init(ast: *Ast, symtab: *SymbolTable, allocator: std.mem.Allocator) Self {
    return .{
        .ast    = ast,
        .symtab = symtab,
        .errors = std.ArrayList(Error).init(allocator),
        .return_type = .none,
        .param_index = 0,
    };
}

pub fn deinit(self: *Self) void {
    self.errors.deinit();
}

pub fn check(self: *Self) !void {
    
    _ = try self.checkNode(self.ast.root);
    if (self.errors.items.len > 0) {
        return error.TypeError;
    }
}

fn checkNode(self: *Self, id: usize) !Type {

    const node = &self.ast.nodes.items[id];

    switch (node.*) {
        
        .empty,
        .break_statement,
        .continue_statement,
        .parameter_list, => return .none,

        .parenthesized => |v| return self.checkNode(v.content),

        .constant => |v| return v.type_,

        .variable => |v|
            return self.symtab.symbols.items[v.symbol].type_,

        // UNARY
        .unary => |v| {

            const operand = try self.checkNode(v.operand);
            const expected: Type = switch (v.operator.kind) {
                .@"-" => .integer,
                .@"!" => .boolean,
                else => unreachable, // illegal token in unary
            };

            if (operand != expected) {
                try self.pushError(.{
                    .stage = .typechecking,
                    .where = v.operator.where,
                    .kind = .{ 
                        .operator_mismatch = .{
                            .expected = expected,
                            .found    = operand,
                        },
                    },
                });
                unreachable;
            }
            return operand;
        },

        // BINARY
        .binary => |v| {

            const left = try self.checkNode(v.left);
            const right = try self.checkNode(v.right);

            if (left != right) {
                try self.pushError(.{
                    .stage = .typechecking,
                    .where = v.operator.where,
                    .kind = .{
                        .binary_mismatch = .{
                            .left = left,
                            .right = right, 
                        },
                    },
                });
                unreachable;
            }

            const operands = left;

            const expected: Type = switch (v.operator.kind) {

                // Applies to all types
                .@"==",
                .@"!=" => return .boolean,

                // Logical operator
                .@"and",
                .@"or" => .boolean,

                // Arithmetic
                .@"+",
                .@"-",
                .@"*",
                .@"/",
                .@"%" => .integer,

                // Arithmetic comparisons
                .@"<",
                .@"<=",
                .@">",
                .@">=" => {
                    if (operands != .integer) {
                        try self.pushError(.{
                            .stage = .typechecking,
                            .where = v.operator.where,
                            .kind = .{
                                .operator_mismatch = .{
                                    .expected = .integer,
                                    .found = .boolean,
                                },
                            },
                        });
                        unreachable;
                    }
                    return .boolean;
                },
                else => unreachable, // illegal token in binary
            };

            // Reach this when operands match result
            if (operands != expected) {
                try self.pushError(.{
                    .stage = .typechecking,
                    .where = v.operator.where,
                    .kind  = .{
                        .operator_mismatch = .{
                            .expected = expected,
                            .found    = operands,
                        },
                    },
                });
                unreachable;
            }

            return operands;
        },

        // TOPLEVEL
        .toplevel_list => |v| {
            _ = try self.checkNode(v.decl);
            if (v.next) |next| {
                _ = try self.checkNode(next);
            }
            return .none;
        },

        // FUNCTION
        .function => |v| {
            self.return_type = v.return_type;
            _ = try self.checkNode(v.body);
            return .none;
        },

        // BLOCK
        .block => |v| {
            _ = try self.checkNode(v.content);
            return .none;
        },

        // STATEMENT
        .statement_list => |v| {
            // We stop propagation of error to sync at statements
            _ = self.checkNode(v.statement) catch .none;
            if (v.next) |next| {
                _ = try self.checkNode(next);
            }
            return .none;
        },

        // DECLARATION
        .declaration => |v| {

            const expr = try self.checkNode(v.expr);
            const expected = self.symtab.symbols.items[v.symbol].type_;

            if (expr != expected) {
                try self.pushError(.{
                    .stage = .typechecking,
                    .where = v.name.where,
                    .kind = .{
                        .assignment_mismatch = .{
                            .expected = expected,
                            .found = expr,
                        },
                    },
                });
                unreachable;
            }

            return .none;
        },

        // ASSIGNMENT
        .assignment => |v| {

            const expr = try self.checkNode(v.expr);
            const expected = self.symtab.symbols.items[v.symbol].type_;

            if (expr != expected) {
                try self.pushError(.{
                    .stage = .typechecking,
                    .where = v.operator.where,
                    .kind = .{
                        .assignment_mismatch = .{
                            .expected = expected,
                            .found = expr,
                        },
                    },
                });
                unreachable;
            }

            return .none;
        },

        // IF
        .if_statement => |v| {

            const condition = try self.checkNode(v.condition);

            if (condition != .boolean) {
                try self.pushError(.{
                    .stage = .typechecking,
                    .where = v.keyword.where,
                    .kind = .control_flow_mismatch,
                });
                unreachable;
            }

            _ = try self.checkNode(v.block);
            if (v.else_block) |else_block| {
                _ = try self.checkNode(else_block);
            }

            return .none;
        },

        // WHILE
        .while_statement => |v| {

            const condition = try self.checkNode(v.condition);

            if (condition != .boolean) {
                try self.pushError(.{
                    .stage = .typechecking,
                    .where = v.keyword.where,
                    .kind = .control_flow_mismatch,
                });
                unreachable;
            }

            _ = try self.checkNode(v.block);

            return .none;
        },

        // RETURN
        .return_statement => |v| {

            if (v.expr) |expr| {
                const expr_type = try self.checkNode(expr);            
                if (expr_type != self.return_type) {
                    try self.pushError(.{
                        .stage = .typechecking,
                        .where = v.keyword.where,
                        .kind = .{ 
                            .return_mismatch = .{
                                .expected = self.return_type,
                                .found = expr_type,
                            },
                        },
                    });
                    unreachable;
                }
            }

            return .none;
        },

        .call => |v| {

            const symbol = self.symtab.symbols.items[v.symbol];
            const return_type = symbol.type_;
            const func = switch (symbol.kind) {
                .function => |f| f,
                else => unreachable,
            };

            if (v.args) |args| {
                self.param_index = func.params.?;
                _ = try self.checkNode(args);
            }
            // functions always return integers
            return return_type;
        },

        .argument_list => |v| {

            const argument = try self.checkNode(v.expr);
            const param = switch (self.ast.nodes.items[self.param_index]) {
                .parameter_list => |p| p,
                else => unreachable,
            };

            if (argument != param.type_) {
                try self.pushError(.{
                    .stage = .typechecking,
                    .where = v.delimiter.where,
                    .kind = .{ 
                        .argument_mismatch = .{
                            .expected = param.type_,
                            .found    = argument,
                        }, 
                    },
                });
                unreachable;
            }

            if (v.next) |next| {
                self.param_index = param.next.?;
                _ = try self.checkNode(next);
            }

            return .none;
        },

        // PRINT
        .print_statement => |v| {

            _ = try self.checkNode(v.expr);
            return .none;
        },
    }
}

fn pushError(self: *Self, err: Error) !void {
    
   try self.errors.append(err);
   return error.TypeError;
}
