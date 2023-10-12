
const std  = @import("std");
const Ast  = @import("Ast.zig");

const Self = @This();

pub const Error = struct {

    begin: usize,
    end: usize,

    kind: enum {
        redeclaration,
        undeclared,
    }
};

pub const Scope = enum {
    global,
    local,
};

ast:       *Ast,
source:    []const u8,
symbols:   std.ArrayList(Scope),
maps:      std.ArrayList(std.StringHashMap(usize)),
map_id:    usize,
errors: std.ArrayList(Error),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, ast: *Ast, source: []const u8) !Self {

    var self: Self = .{
        .ast       = ast,
        .source    = source,
        .symbols   = std.ArrayList(Scope).init(allocator),
        .maps      = std.ArrayList(std.StringHashMap(usize)).init(allocator),
        .map_id    = 0,
        .errors    = std.ArrayList(Error).init(allocator),
        .allocator = allocator,
    };

    try self.maps.append(std.StringHashMap(usize).init(allocator)); 
    return self;
}

pub fn resolve(self: *Self) !void {
    
    try self.resolve_(self.ast.root);
}

fn currentScope(self: *Self) Scope {
    
    return if (self.map_id == 0) .global else .local;
}

fn pushScope(self: *Self) !void {

    self.map_id += 1;
    errdefer self.map_id -= 1;

    if (self.map_id == self.maps.items.len) {
        try self.maps.append(std.StringHashMap(usize).init(self.allocator));
    }
}

fn popScope(self: *Self) !void {

    if (self.map_id == 0) {
        return error.PopError;
    }

    self.maps.items[self.map_id].clearRetainingCapacity();

    self.map_id -= 1;
}

fn pushError(self: *Self, err: Error) !void {

    try self.errors.append(err);
    return error.ResolutionError;
}

fn pushSymbol(self: *Self) !usize {

    const symbol = self.symbols.items.len;
    try self.symbols.append(self.currentScope());
    return symbol;
}

fn declare(self: *Self, begin: usize, end: usize) !usize {
    
    var current = &self.maps.items[self.map_id];
    const name = self.source[begin..end];

    if (current.get(name)) |_| {

        try self.pushError(.{
            .begin = begin,
            .end   = end,
            .kind  = .redeclaration,
        });
    }

    const symbol = try self.pushSymbol();
    try current.put(name, symbol);
    return symbol;
}

fn reference(self: *Self, begin: usize, end: usize) !usize {

    const name = self.source[begin..end];

    var index = self.map_id;
    while (true) {

        var current = &self.maps.items[index];
        if (current.get(name)) |symbol| {
            return symbol;
        } 

        if (index == 0) break;
        index -= 1;
    }

    try self.pushError(.{
        .begin = begin,
        .end   = end,
        .kind  = .undeclared,
    });

    unreachable;
}

fn resolve_(self: *Self, index: usize) !void {

    var node = &self.ast.nodes[index];

    switch (node.*) {

        .empty, .break_statement => {},
        
        .statement_list => |v| {
            try self.resolve_(v.first); 
            try self.resolve_(v.follow); 
        },

        .block => |v| {
            try self.pushScope();
            try self.resolve_(v.content);
            try self.popScope();
        },

        .declaration => |*v| {
            // Resolve exression first so declaration of symbol
            //  doesn't reference itself
            try self.resolve_(v.expression);
            v.symbol = try self.declare(v.identifier.begin, v.identifier.end);
        },

        .assignment => |*v| {
            v.symbol = try self.reference(v.identifier.begin, v.identifier.end);
            try self.resolve_(v.expression);
        },

        .print_statement => |v| try self.resolve_(v.argument),

        .if_statement => |v| {
            try self.resolve_(v.condition);
            try self.resolve_(v.block);
            if (v.else_block) |else_block| {
                try self.resolve_(else_block);
            }
        },

        .while_statement => |v| {
            try self.resolve_(v.condition); 
            try self.resolve_(v.block);
        }, 

        .unary => |v| try self.resolve_(v.operand),

        .binary => |v| {
            try self.resolve_(v.left);
            try self.resolve_(v.right);
        },

        .atomic => |*v| switch (v.token.kind) {
            .identifier => v.symbol = try self.reference(v.token.begin, v.token.end),
            .literal    => v.literal = self.source[v.token.begin..v.token.end],
            else => unreachable,
        },
    }
}
