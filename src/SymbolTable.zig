
const std = @import("std");
const Self = @This();

const Ast   = @import("Ast.zig");
const Error = @import("Error.zig");

const Symbol = struct {
    name: []const u8,
    kind: union(enum) {
        function: usize,
        variable: union(enum) {
            global,
            local: usize,
            param: struct {
                stack: usize,
                register: usize,
            },
        }
    },
};

allocator:      std.mem.Allocator,
ast:            *Ast,
errors:         std.ArrayList(Error),
symbols:        std.ArrayList(Symbol),
scopes:         std.ArrayList(std.StringHashMap(usize)),
current_scope:  usize,
param_counter:  usize,
arg_counter:    usize,
stack_counter:  usize,
symbol_counter: usize,

pub fn init(ast: *Ast, allocator: std.mem.Allocator) !Self {

    var self: Self = .{
        .allocator      = allocator,
        .ast            = ast,
        .errors         = std.ArrayList(Error).init(allocator),
        .symbols        = std.ArrayList(Symbol).init(allocator),
        .scopes         = std.ArrayList(std.StringHashMap(usize)).init(allocator),
        .current_scope  = 0,
        .param_counter  = 0,
        .arg_counter    = 0,
        .stack_counter  = 0,
        .symbol_counter = 0,
    };

    // push global scope
    try self.scopes.append(std.StringHashMap(usize).init(allocator));
    return self;
}

pub fn deinit(self: *Self) void {

    for (self.scopes.items) |*scope| {
        scope.deinit();
    }

    self.scopes.deinit();
    self.symbols.deinit();
    self.errors.deinit();
}

pub fn getSymbol(self: *Self, symbol: usize) Symbol {
    return self.symbols.items[symbol];
}

pub fn resolve(self: *Self) !void {

    try self.resolveNode(self.ast.root);
    if (self.errors.items.len > 0) {
        return error.ResolutionError;
    }
}

fn pushError(self: *Self, err: Error) !void {

    try self.errors.append(err);
    return error.ResolutionError;
}

fn pushScope(self: *Self) !void {

    self.current_scope += 1;
    
    if (self.current_scope == self.scopes.items.len) {
        try self.scopes.append(std.StringHashMap(usize).init(self.allocator));
    }
}

fn popScope(self: *Self) void {
    
    self.scopes.items[self.current_scope].clearRetainingCapacity();
    self.current_scope -= 1;
}

fn setParamCount(self: *Self, id: usize, count: usize) void {

    var symbol = &self.symbols.items[id];
    switch (symbol.kind) {
        .function => |*v| v.* = count,
        else => unreachable, // attempt to set param count for non-function
    }
}

fn pushSymbol(self: *Self, symbol: Symbol) !usize {
    
    const index = self.symbols.items.len;
    try self.symbols.append(symbol);
    _ = try self.scopes.items[self.current_scope].put(symbol.name, index);
    return index;
}

fn matchParamCount(self: *Self, symbol_1: Symbol, symbol_2: Symbol) !void {

    switch (symbol_1.kind) {
        .function => |v1| switch (symbol_2.kind) {
            .function => |v2| {
                if (v1 != v2) {
                    try self.pushError(.{
                        .stage = .symbol_resolution,
                        .where = symbol_2.name,
                        .kind = .{
                            .param_count_mismatch = .{
                                .expected = v1,
                                .found = v2,
                            },
                        },
                    });
                }
            },
            else => {}
        },
        else => {}
    }
}

fn declare(self: *Self, symbol: Symbol) !usize {

    const scope_id = switch (symbol.kind) {
        .variable => self.current_scope,
        .function => 0,
    };

    var scope = &self.scopes.items[scope_id];

    if (scope.get(symbol.name)) |collision_id| {
        const collision = self.symbols.items[collision_id];
        try self.pushError(.{
            .stage = .symbol_resolution,
            .where = symbol.name,
            .kind = .{ .redeclaration = collision.name, },
        });
        unreachable;
    }

    return try self.pushSymbol(symbol);
}

fn reference(self: *Self, symbol: Symbol) !usize {

    // TODO?: Disallow variables with same name as function

    var scope_id = switch (symbol.kind) {
        .variable => self.current_scope,
        .function => 0,
    };

    while (true) : (scope_id -= 1) {

        var scope = &self.scopes.items[scope_id];

        if (scope.get(symbol.name)) |match_id| {
            const match = self.symbols.items[match_id];
            try self.matchParamCount(match, symbol);
            return match_id;
        }

        if (scope_id == 0) {
            break;
        }
    }

    try self.pushError(.{
        .stage = .symbol_resolution,
        .where = symbol.name,
        .kind = .undeclared_ref,
    });
    unreachable;
}

fn resolveNode(self: *Self, id: usize) !void {

    var node = &self.ast.nodes.items[id];
    switch (node.*) {

        .empty,
        .break_statement,
        .continue_statement,
        .constant  => {},

        .toplevel_list => |*v| {
            try self.resolveNode(v.decl);
            if (v.next) |next| {
                try self.resolveNode(next);
            }
        },

        .function => |*v| {
            v.symbol = try self.declare(
                .{ 
                    .name = v.name.where,
                    .kind = .{ .function = undefined, },
                },
            );
            try self.pushScope();
            if (v.params) |params| {
                self.param_counter = 0;
                self.stack_counter = 0;
                try self.resolveNode(params);
            }
            self.setParamCount(v.symbol, self.param_counter);
            // We don't want to push scope twice,
            //  so unwrap the block
            //  and resolve the content
            switch (self.ast.nodes.items[v.body]) {
                .block => |b| try self.resolveNode(b.content),
                else => unreachable,
            }
            self.popScope();
        },

        .parameter_list => |*v| {
            v.symbol = try self.declare(.{
                .name = v.name.where,
                .kind = .{
                    .variable = .{
                        .param = .{
                            .stack = self.stack_counter,
                            .register = self.param_counter,
                        },
                    }
                },
            });
            self.param_counter += 1;
            self.stack_counter += 1;
            if (v.next) |next| {
                try self.resolveNode(next);
            }            
        },

        .block => |*v| {
            try self.pushScope();
            try self.resolveNode(v.content);
            self.popScope();
        },

        .statement_list => |*v| {
            try self.resolveNode(v.statement);
            if (v.next) |next| {
                try self.resolveNode(next);
            }
        },

        .declaration => |*v| {
            // resolve expression first so declaration
            //  doesn't reference itself
            self.stack_counter += 1;
            try self.resolveNode(v.expr);
            v.symbol = try self.declare(.{
                .name = v.name.where,
                .kind = .{
                    .variable = .{ .local = self.stack_counter, },
                },
            });
        },

        .assignment => |*v| {
            v.symbol = try self.reference(.{
                .name = v.name.where,
                .kind = .{ .variable = undefined, },
            });
            try self.resolveNode(v.expr);
        },

        .call => |*v| {
            self.arg_counter = 0;
            if (v.args) |args| {
                try self.resolveNode(args);
            }
            v.symbol = try self.reference(.{
                .name = v.name.where,
                .kind = .{ .function = self.arg_counter, },
            });
        },

        .argument_list => |*v| {
            try self.resolveNode(v.expr);
            self.arg_counter += 1;
            if (v.next) |next| {
                try self.resolveNode(next);
            }
        },

        .binary => |*v| {
            try self.resolveNode(v.left);
            try self.resolveNode(v.right);
        },

        .unary => |*v| {
            try self.resolveNode(v.operand);
        },

        .return_statement => |*v| {
            if (v.expr) |expr| {
                try self.resolveNode(expr);
            }
        },

        .variable => |*v| {
            v.symbol = try self.reference(.{
                .name = v.name.where,
                .kind = .{ .variable = undefined, },
            });
        },

        .print_statement => |v| {
            try self.resolveNode(v.expr);
        },

        .if_statement => |v| {
            try self.resolveNode(v.condition);
            try self.resolveNode(v.block);
            if (v.else_block) |else_block| {
                try self.resolveNode(else_block);
            }
        },

        .while_statement => |v| {
            try self.resolveNode(v.condition);
            try self.resolveNode(v.block);
        },
    }
}

pub fn dump(self: *Self, writer: anytype) !void {

    try writer.print("---------- Symbol Table Dump ----------\n", .{});
    for (self.symbols.items, 0..) |symbol, i| {
        try writer.print("Symbol {s} ({d}): ", .{ symbol.name, i, });
        switch (symbol.kind) {
            .function => |v| try writer.print("function with {d} parameter(s)\n", .{ v, }),
            .variable => |v| switch (v) {
                .param  => |u| try writer.print("param ({d}/{d})\n", .{ u.register, u.stack, }),
                .local  => |u| try writer.print("local ({d})\n", .{ u, }),
                .global => try writer.print("global\n", .{}),
            }
        }
    } 
}
