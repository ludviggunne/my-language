
const std = @import("std");

const Ast          = @import("ast.zig").Ast;
const Node         = @import("ast.zig").Node;
const Token        = @import("Token.zig");
const RegisterPool = @import("RegisterPool.zig");
const Register     = RegisterPool.Register;
const InternPool   = @import("InternPool.zig");

const Self = @This();

const Section       = std.ArrayList(u8);
const SectionWriter = @typeInfo(@TypeOf(Section.writer)).Fn.return_type.?;

pub const Error = union(enum) {
    undeclared_variable: struct {
        begin: usize,
        end:   usize,
    },
    redeclaration: struct {
        begin: usize,
        end:   usize,
    },
};

ast:           *const Ast,
text_section:  Section,
data_section:  Section,
text_writer:   SectionWriter,
data_writer:   SectionWriter,
register_pool: RegisterPool,
intern_pool:   InternPool,
source:        []const u8,
errors:        std.ArrayList(Error),
label_counter: usize,

pub fn init(ast: *const Ast, allocator: std.mem.Allocator, source: []const u8) Self {

    var text_section = Section.init(allocator);
    var data_section = Section.init(allocator);

    return .{
        .ast           = ast,
        .text_section  = text_section,
        .data_section  = data_section,
        .text_writer   = undefined,
        .data_writer   = undefined,
        .register_pool = RegisterPool.init(),
        .intern_pool   = InternPool.init(allocator),
        .source        = source,
        .errors        = std.ArrayList(Error).init(allocator),
        .label_counter = 0,
    };
}

pub fn initWriters(self: *Self) void {

    self.text_writer = self.text_section.writer();
    self.data_writer = self.data_section.writer();
}

pub fn generate(self: *Self) !void {

    const result = try self.generate_(&self.ast.nodes[self.ast.root]);  
    self.register_pool.deallocate(result);
}

pub fn output(self: *Self, writer: anytype) !void {

    try writer.print(
        \\.section .text
        \\    .globl main
        \\main:
        \\{0s}
        \\    movq     $60, %rax
        \\    movq     $0, %rdi
        \\    syscall
        \\.section .data
        \\    __fmt: .asciz "%d\n"
        \\{1s}
        , 
            .{
                self.text_section.items,
                self.data_section.items,       
            }
        );
}

fn tokenString(self: *Self, token: Token) []const u8 {

    return self.source[token.begin..token.end];
}

fn newLabel(self: *Self) usize {

    defer self.label_counter += 1;
    return self.label_counter;
}

fn generate_(self: *Self, node: *const Node) anyerror!Register {

    const result = switch (node.*) {

        // We need to return something ...
        .empty => try self.register_pool.allocate(),

        .statement_list => |v| try self.statementList(v),

        .binary => |v| switch (v.operator.kind) {

            .@"<",
            .@"<=",
            .@"==",
            .@">",
            .@">=",
            .@"!=", => try self.comparison(v),

            .@"+",
            .@"-",
            .@"*",
            .@"/",
            .@"%", => try self.arithmetic(v),

            else => unreachable, // codegen for operator not implemented
        },

        .unary           => |v| try self.unary(v),
        .if_statement    => |v| try self.ifStatement(v),
        .while_statement => |v| try self.whileStatement(v),
        .print_statement => |v| try self.printStatement(v),
        .block           => |v| try self.block(v),
        .declaration     => |v| try self.declaration(v),
        .assignment      => |v| try self.assignment(v),
        .atomic          => |v| try self.atomic(v),
    };

    return result;
}

fn printStatement(self: *Self, node: anytype) anyerror!Register {

    const argument = &self.ast.nodes[node.argument];
    const argument_register = try self.generate_(argument);
    defer self.register_pool.deallocate(argument_register);

    try self.text_writer.print(
        \\    push     %rbp
        \\    leaq     __fmt(%rip), %rdi
        \\    movq     %{0s}, %rsi
        \\    movq     $0, %rax
        \\    call     printf
        \\    pop      %rbp
        \\
        , .{
            @tagName(argument_register),
        }
    );

    return argument_register;
}

fn block(self: *Self, node: anytype) anyerror!Register {

    const content = &self.ast.nodes[node.content]; 
    return try self.generate_(content);
}

fn whileStatement(self: *Self, node: anytype) anyerror!Register {

    const begin_label = self.newLabel();
    const done_label = self.newLabel();

    try self.text_writer.print(
        \\.L{0d}:
        \\
        , .{
            begin_label,
        }
    );

    const condition = &self.ast.nodes[node.condition];
    const condition_register = try self.generate_(condition);
    defer self.register_pool.deallocate(condition_register);

    try self.text_writer.print(
        \\    cmpq     $0, %{0s}
        \\    je       .L{1d}
        \\
        , .{
            @tagName(condition_register),
            done_label,
        }
    );

    const block_ = &self.ast.nodes[node.block];
    const block_register = try self.generate_(block_);
    defer self.register_pool.deallocate(block_register);

    try self.text_writer.print(
        \\    jmp      .L{0d}
        \\.L{1d}:
        \\
        , .{
            begin_label,
            done_label,
        }
    );

    return block_register;
}

fn ifStatement(self: *Self, node: anytype) anyerror!Register {

    const condition = &self.ast.nodes[node.condition];
    const condition_register = try self.generate_(condition);
    defer self.register_pool.deallocate(condition_register);

    const done_label = self.newLabel();
    const has_else = node.else_block != null;
    const else_label = if (has_else) self.newLabel() else undefined;

    try self.text_writer.print(
        \\    cmpq     $0, %{0s}
        \\    je       .L{1d}
        \\
        , .{
            @tagName(condition_register),
            if (has_else) else_label else done_label,
        }
    );

    const block_ = &self.ast.nodes[node.block];
    const block_register = try self.generate_(block_);
    defer self.register_pool.deallocate(block_register);

    if (has_else) {
        try self.text_writer.print(
            \\    jmp      .L{0d}
            \\.L{1d}:
            \\
            , .{
                done_label,
                else_label,
            }
        );

        const else_ = &self.ast.nodes[node.else_block.?];
        const else_register = try self.generate_(else_);
        defer self.register_pool.deallocate(else_register);
    }

    try self.text_writer.print(
        \\.L{0d}:
        \\
        , .{
            done_label,
        }
    );

    return block_register;
}

fn assignment(self: *Self, node: anytype) anyerror!Register {

    const name = self.tokenString(node.identifier);

    if (self.intern_pool.get(name) == null) {

        try self.errors.append(
            .{
                .undeclared_variable = .{
                    .begin = node.identifier.begin,
                    .end   = node.identifier.end,
                },
            }
        );
        return error.UndeclaredVariable;
    }

    const expression = &self.ast.nodes[node.expression];
    const expression_register = try self.generate_(expression);
    defer self.register_pool.deallocate(expression_register);

    const scratch_register = try self.register_pool.allocate();
    defer self.register_pool.deallocate(scratch_register);
    
    switch (node.operator.kind) {

        .@"=" => try self.text_writer.print(
            \\    movq     %{0s}, var_{1s}(%rip)
            \\
            , .{
                @tagName(expression_register),
                name,
            }
        ),

        .@"+=" => try self.text_writer.print(
            \\    movq     var_{0s}(%rip), %{1s}
            \\    addq     %{2s}, %{1s}
            \\    movq     %{1s}, var_{0s}(%rip)
            \\
            , .{
                name,
                @tagName(scratch_register),
                @tagName(expression_register),
            }
        ),

        .@"-=" => try self.text_writer.print(
            \\    movq     var_{0s}(%rip), %{1s}
            \\    subq     %{2s}, %{1s}
            \\    movq     %{1s}, var_{0s}(%rip)
            \\
            , .{
                name,
                @tagName(scratch_register),
                @tagName(expression_register),
            }
        ),

        .@"*=" => try self.text_writer.print(
            \\    movq     var_{0s}(%rip), %rax
            \\    imulq    %{1s}
            \\    movq     %rax, var_{0s}(%rip)
            \\
            , .{
                name,
                @tagName(expression_register),
            }
        ),

        .@"/=" => try self.text_writer.print(
            \\    movq     var_{0s}(%rip), %rax
            \\    cqo
            \\    idivq    %{1s}
            \\    movq     %rax, var_{0s}(%rip)
            \\
            , .{
                name,
                @tagName(expression_register),
            }
        ),

        .@"%=" => try self.text_writer.print(
            \\    movq     var_{0s}(%rip), %rax
            \\    cqo
            \\    idivq    %{1s}
            \\    movq     %rdx, var_{0s}(%rip)
            \\
            , .{
                name,
                @tagName(expression_register),
            }
        ),

        else => unreachable, // codegen for assignment operator not implemented
    } 

    return expression_register;
}

fn declaration(self: *Self, node: anytype) anyerror!Register {

    const name = self.tokenString(node.identifier);

    if (self.intern_pool.get(name)) |_| {

        try self.errors.append(
            .{ .redeclaration =
                .{
                    .begin = node.identifier.begin,
                    .end   = node.identifier.end,
                }
            }
        );

        return error.Redeclaration;
    }

    _ = try self.intern_pool.getDeclare(name);

    try self.data_writer.print(
        \\    var_{0s}: .quad 0
        \\
        , .{
            name,
        }
    );

    const expression = &self.ast.nodes[node.expression];
    const expression_register = try self.generate_(expression);

    // This is a statement so we can discard register
    defer self.register_pool.deallocate(expression_register);

    try self.text_writer.print(
        \\    movq     %{0s}, var_{1s}(%rip)
        \\
        , .{
            @tagName(expression_register),
            name,
        }
    );

    return expression_register;
}

fn comparison(self: *Self, node: anytype) anyerror!Register {

    const left  = &self.ast.nodes[node.left];
    const right = &self.ast.nodes[node.right];

    const left_register  = try self.generate_(left);
    const right_register = try self.generate_(right);

    defer self.register_pool.deallocate(left_register);

    const true_label  = self.newLabel();
    const done_label  = self.newLabel();

    const jump_instruction: []const u8 = switch (node.operator.kind) {
        .@"==" => "je  ",
        .@"!=" => "jne ",
        .@">"  => "jg  ",
        .@">=" => "jge ",
        .@"<"  => "jl  ",
        .@"<=" => "jle ",
        else   => unreachable, // codegen for comparison operator not implemented
    };

    try self.text_writer.print(
        \\    cmpq     %{0s}, %{1s}
        \\    {2s}     .L{3d}
        \\    movq     $0, %{1s}
        \\    jmp      .L{4d}
        \\.L{3d}:
        \\    movq     $1, %{1s}
        \\.L{4d}:
        \\
        , .{
            @tagName(right_register), // 0
            @tagName(left_register),  // 1
            jump_instruction,         // 2
            true_label,               // 3
            done_label,               // 4
        }
    );

    return left_register;
}

fn statementList(self: *Self, node: anytype) anyerror!Register {

    const first  = &self.ast.nodes[node.first];
    const follow = &self.ast.nodes[node.follow];

    const first_register  = try self.generate_(first);
    const follow_register = try self.generate_(follow);

    // We can discard results from statements
    self.register_pool.deallocate(first_register);
    self.register_pool.deallocate(follow_register);
    return follow_register; 
}

fn arithmetic(self: *Self, node: anytype) anyerror!Register {

    // !!! Operands are switched

    const left  = &self.ast.nodes[node.left];
    const right = &self.ast.nodes[node.right];

    const left_register  = try self.generate_(left);
    const right_register = try self.generate_(right);

    defer self.register_pool.deallocate(left_register);

    switch (node.operator.kind) {

        .@"+" => try self.text_writer.print(
            \\    addq     %{0s}, %{1s}
            \\
            , .{
                @tagName(right_register),
                @tagName(left_register),
            }
        ),

        .@"-" => try self.text_writer.print(
            \\    subq     %{0s}, %{1s}
            \\
            , .{
                @tagName(right_register),
                @tagName(left_register),
            }
        ),

        .@"*" => try self.text_writer.print(
            \\    movq     %{0s}, %rax
            \\    imulq    %{1s}
            \\    movq     %rax, %{1s}
            \\
            , .{
                @tagName(right_register),
                @tagName(left_register),
            }
        ),

        .@"/" => try self.text_writer.print(
            \\    movq     %{1s}, %rax
            \\    cqo
            \\    idivq    %{0s}
            \\    movq     %rax, %{1s}
            \\
            , .{
                @tagName(right_register),
                @tagName(left_register),
            }
        ),

        .@"%" => try self.text_writer.print(
            \\    movq     %{1s}, %rax
            \\    cqo
            \\    idivq    %{0s}
            \\    movq     %rdx, %{1s}
            \\
            , .{
                @tagName(right_register),
                @tagName(left_register),
            }
        ),

        else => unreachable, // codegen for arithmetic operator not implemented
    }

    return left_register;
}

fn unary(self: *Self, node: anytype) anyerror!Register {

    const operand = &self.ast.nodes[node.operand];
    const operand_register = try self.generate_(operand);

    const scratch_register = try self.register_pool.allocate();
    defer self.register_pool.deallocate(scratch_register);

    switch (node.operator.kind) {

        .@"!" => try self.text_writer.print(
            \\    movq     $1, %{0s}
            \\    xorq     %{0s}, %{1s}
            \\    
            , .{
                @tagName(scratch_register),
                @tagName(operand_register),
            }
        ),

        .@"-" => try self.text_writer.print(
            \\    negq %{0s}
            \\
            , .{
                @tagName(operand_register),
            }
        ),

        else => unreachable, // codegen for unary operator not implemented
    }


    return operand_register; 
}

fn atomic(self: *Self, node: anytype) anyerror!Register {
    
    const result = try self.register_pool.allocate();

    switch (node.token.kind) {

        .identifier => {
            
            if (self.intern_pool.get(self.tokenString(node.token))) |_| {

                try self.text_writer.print(
                    \\    movq     var_{0s}(%rip), %{1s}
                    \\
                    , .{
                        self.tokenString(node.token),
                        @tagName(result),
                    }
                );

            } else {

                try self.errors.append(
                    .{
                        .undeclared_variable = .{
                            .begin = node.token.begin,
                            .end   = node.token.end,
                        },
                    }       
                );

                return error.UndeclaredVariable;
            }
        },

        .literal => {
            
            try self.text_writer.print(
                \\    movq     ${0s}, %{1s}
                \\
                , .{
                    self.tokenString(node.token),
                    @tagName(result), 
                }
            );
        },

        else => unreachable, // codegen for atomic variant not implemented
    }

    return result;
}
