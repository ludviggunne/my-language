
const Self = @This();

const Ast = @import("Ast.zig");
const Type = @import("types.zig").Type;

ast: *Ast,
indents: usize,

pub fn init(ast: *Ast) Self {

    return .{
        .ast     = ast,
        .indents = 0,
    };
}

pub fn format(self: *Self, writer: anytype) !void {

    try self.formatNode(self.ast.root, writer);
}

fn newLine(writer: anytype) !void {
    try writer.print("\n", .{});
}

fn indent(self: *Self) void {

    self.indents += 1;
}

fn unIndent(self: *Self) void {

    self.indents -= 1;
}

fn printIndent(self: *Self, writer: anytype) !void {

    for (0..self.indents) |_| try writer.print("    ", .{});
}

fn typeStr(type_: Type) []const u8 {

    return switch (type_) {
        .integer => "int",
        .boolean => "bool",
        else => unreachable,
    };
}

fn formatNode(self: *Self, id: usize, writer: anytype) !void {

    const node = self.ast.nodes.items[id];

    switch (node) {

        .empty => {},

        .break_statement => {
            try self.printIndent(writer);
            try writer.print("break;\n", .{});
            try newLine(writer);
        },

        .continue_statement => {
            try self.printIndent(writer);
            try writer.print("continue;\n", .{});
            try newLine(writer);
        },

        .toplevel_list => |v| {
            try self.formatNode(v.decl, writer);
            if (v.next) |next| {
                try newLine(writer);
                try self.formatNode(next, writer);
            }
        },

        .function => |v| {
            try writer.print("fn {0s}(", .{ v.name.where, });
            if (v.params) |params| {
                try self.formatNode(params, writer);
            }
            switch (v.return_type) {
                .none => try writer.print(") = ", .{}),
                else => try writer.print("): {0s} = ", .{ typeStr(v.return_type), }),
            }
            try self.formatNode(v.body, writer);
            try newLine(writer);
        },

        .parameter_list => |v| {
            try writer.print("{0s}: {1s}", .{ v.name.where, typeStr(v.type_), });
            if (v.next) |next| {
                try writer.print(", ", .{});
                try self.formatNode(next, writer);
            }
        },

        .declaration => |v| {
            try self.printIndent(writer);
            switch (v.type_) {
                .none => try writer.print("let {0s} = ", .{ v.name.where, }),
                else => try writer.print("let {0s}: {1s} = ", .{ v.name.where, typeStr(v.type_), }),
            }
            try self.formatNode(v.expr, writer);
            try writer.print(";", .{});
            try newLine(writer);
        },

        .assignment => |v| {
            try self.printIndent(writer);
            try writer.print("{0s} {1s} ", .{ v.name.where, @tagName(v.operator.kind), });
            try self.formatNode(v.expr, writer);
            try writer.print(";", .{});
            try newLine(writer);
        },

        .binary => |v| {
            try self.formatNode(v.left, writer);
            try writer.print(" {0s} ", .{ @tagName(v.operator.kind), });
            try self.formatNode(v.right, writer);
        },

        .unary => |v| {
            try writer.print("{0s}", .{ @tagName(v.operator.kind), });
            try self.formatNode(v.operand, writer);
        },

        .call => |v| {
            try writer.print("{0s}(", .{ v.name.where, });
            if (v.args) |args| {
                try self.formatNode(args, writer);
            }
            try writer.print(")", .{});
        },

        .argument_list => |v| {
            try self.formatNode(v.expr, writer);
            if (v.next) |next| {
                try writer.print(", ", .{});
                try self.formatNode(next, writer);
            }
        },

        .block => |v| {
            try writer.print("{{\n", .{});
            self.indent();
            try self.formatNode(v.content, writer);
            self.unIndent();
            try self.printIndent(writer);
            try writer.print("}}", .{});
        },

        .statement_list => |v| {
            try self.formatNode(v.statement, writer);
            if (v.next) |next| {
                try self.formatNode(next, writer);
            }
        },

        .if_statement => |v| {
            try self.printIndent(writer);
            try writer.print("if ", .{});
            try self.formatNode(v.condition, writer);
            try writer.print(" ", .{});
            try self.formatNode(v.block, writer);
            if (v.else_block) |else_block| {
                try writer.print(" else ", .{});
                try self.formatNode(else_block, writer);
            }
            try newLine(writer);
        },

        .while_statement => |v| {
            try self.printIndent(writer);
            try writer.print("while ", .{});
            try self.formatNode(v.condition, writer);
            try writer.print(" ", .{});
            try self.formatNode(v.block, writer);
            try newLine(writer);
        },

        .return_statement => |v| {
            try self.printIndent(writer);
            try writer.print("return", .{});
            try writer.print(" ", .{});
            try self.formatNode(v.expr, writer);
            try writer.print(";", .{});
            try newLine(writer);
        },

        .print_statement => |v| {
            try self.printIndent(writer);
            try writer.print("print ", .{});
            try self.formatNode(v.expr, writer);
            try writer.print(";", .{});
            try newLine(writer);
        },

        .variable => |v| try writer.print("{0s}", .{ v.name.where, }),

        .constant => |v| try writer.print("{0s}", .{ v.token.?.where, }),

        .parenthesized => |v| {
            try writer.print("(", .{});
            try self.formatNode(v.content, writer);
            try writer.print(")", .{});
        },

    }
}
