
const std          = @import("std");
const Self         = @This();
const Ast          = @import("Ast.zig");
const RegisterPool = @import("RegisterPool.zig");
const Register     = RegisterPool.Register;
const SymbolTable  = @import("SymbolTable.zig");
const Error        = @import("Error.zig");

const ArgumentRegister = enum {
    rdi,
    rsi,
    rdx,
    rcx,
};

const LoopState = struct {
    break_label:    usize,
    continue_label: usize,
};

symtab:         *SymbolTable,
ast:            *Ast,
pool:           RegisterPool,
label_counter:  usize,
loop_stack:     std.ArrayList(LoopState),
errors:         std.ArrayList(Error),
current_space:  usize,
current_arg:    usize,

pub fn init(
    ast: *Ast,
    symtab: *SymbolTable,
    allocator: std.mem.Allocator
) Self {

    return .{
        .ast           = ast,
        .symtab        = symtab,
        .pool          = RegisterPool.init(),
        .label_counter = 0,
        .loop_stack    = std.ArrayList(LoopState).init(allocator),
        .errors        = std.ArrayList(Error).init(allocator),
        .current_space = 0,
        .current_arg   = 0,
    };
}

pub fn deinit(self: *Self) void {

    self.errors.deinit();
    self.loop_stack.deinit();
}

pub fn generate(self: *Self, writer: anytype) anyerror!void {

    try writer.print(
       \\.globl main
       \\.section .text
       \\
       , .{}
    );

    _ = try self.generateNode(self.ast.root, writer);

    try writer.print(
        \\.section .data
        \\    __fmt: .asciz "> %d\n"
        \\
        , .{}
    );

    if (self.errors.items.len > 0) {
        return error.CodeGenError;
    }
}

fn generateNode(self: *Self, id: usize, writer: anytype) anyerror!Register {

    const node = self.ast.nodes.items[id];

    return switch (node) {
        .empty              => .none,
        .break_statement    => |v| self.breakStatement(v, writer),
        .continue_statement => |v| self.continueStatement(v, writer),
        .toplevel_list      => |v| self.toplevelList(v, writer),
        .function           => |v| self.function(v, writer),
        .parameter_list     => |v| self.parameterList(v, writer),
        .declaration        => |v| self.declaration(v, writer),
        .assignment         => |v| self.assignment(v, writer),
        .binary             => |v| self.binary(v, writer),
        .unary              => |v| self.unary(v, writer),
        .call               => |v| self.call(v, writer),
        .argument_list      => |v| self.argumentList(v, writer),
        .block              => |v| self.block(v, writer),
        .statement_list     => |v| self.statementList(v, writer),
        .if_statement       => |v| self.ifStatement(v, writer),
        .while_statement    => |v| self.whileStatement(v, writer),
        .return_statement   => |v| self.returnStatement(v, writer),
        .print_statement    => |v| self.printStatement(v, writer),
        .variable           => |v| self.variable(v, writer),
        .constant           => |v| self.constant(v, writer),
        .parenthesized      => |v| self.generateNode(v.content, writer),
    };
}

fn pushError(self: *Self, err: Error) anyerror!void {

    try self.errors.append(err);
    return error.CodeGenError;
}

fn newLabel(self: *Self) usize {
    defer self.label_counter += 1;
    return self.label_counter;
}

fn stackStr(self: *Self, id: usize) anyerror![]const u8 {

    const static = struct {
        var buf: [32]u8 = undefined;
    };

    const symbol = self.symtab.symbols.items[id];
    const stack_id = switch (symbol.kind) {
        .function => unreachable, // function stackStr
        .variable => |u| switch (u) {
            .global => unreachable, // global stackStr
            .local  => |v| v,
            .param  => |v| v,
        },
    };

    const offset = stackOffset(stack_id);
    return std.fmt.bufPrint(&static.buf, "{d}(%rbp)", .{ offset, });
}

fn stackOffset(local_id: usize) i64 {

    const offset: i64 = -8 * @as(i64, @intCast(local_id + 1));
    return offset;
}

fn breakStatement(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const loop_state = self.loop_stack.getLastOrNull() orelse {
        try self.pushError(.{
            .stage = .codegen,
            .where = node,
            .kind = .boc_outside_loop,
        });
        unreachable;
    };

    const label = loop_state.break_label;

    try writer.print(
        \\    jmp      .break_{0d}
        \\
        , .{ label, }
    );

    return .none;
}

fn stackSpace(self: *Self, func: anytype) usize {

    var offset = 8 * func.local_count;

    if (offset % 16 > 0) {
        offset += 8;
    }

    self.current_space = offset;

    return offset;
}

fn continueStatement(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const loop_state = self.loop_stack.getLastOrNull() orelse {
        try self.pushError(.{
            .stage = .codegen,
            .where = node,
            .kind = .boc_outside_loop,
        });
        unreachable;
    };

    const label = loop_state.continue_label;

    try writer.print(
        \\    jmp      .continue_{0d}
        \\
        , .{ label, }
    );

    return .none;
}

fn toplevelList(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    _ = try self.generateNode(node.decl, writer);
    if (node.next) |next| {
        _ = try self.generateNode(next, writer);
    }

    return .none;
}

fn function(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const symbol = self.symtab.symbols.items[node.symbol];
    const func = switch (symbol.kind) {
        .function => |v| v,
        else => unreachable, // tried to unwrap non-function as function
    };

    _ = self.stackSpace(func);

    try writer.print(
        \\{0s}:
        \\
        , .{ node.name.where }
    );

    try self.calleeBegin(writer);

    try spillParams(func.param_count, writer);

    _ = try self.generateNode(node.body, writer);

    if (std.mem.eql(u8, symbol.name, "main")) {
        try writer.print(
            \\    movq     $60, %rax
            \\    movq     $0, %rdi
            \\    syscall
            \\
            , .{}
        );
    }

    return .none;
}

fn parameterList(self: *Self, node: anytype, writer: anytype) anyerror!Register {
    // UNUSED
   _ = .{ self, node, writer, };
   unreachable;
}

fn declaration(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const expr_reg = try self.generateNode(node.expr, writer);
    defer self.pool.free(expr_reg);

    try writer.print(
        \\    movq     %{0s}, {1s}
        \\
        , .{ @tagName(expr_reg), try self.stackStr(node.symbol), }
    );

    return .none;
}

fn assignment(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const load_reg = try self.pool.alloc();
    defer self.pool.free(load_reg);

    const expr_reg = try self.generateNode(node.expr, writer);
    defer self.pool.free(expr_reg);

    switch (node.operator.kind) {

        .@"=" => try writer.print(
            \\    movq     %{0s}, {1s}
            \\
            , .{
                @tagName(expr_reg),
                try self.stackStr(node.symbol),
            }
        ),

        .@"+=" => try writer.print(
            \\    movq     {0s}, %{1s}
            \\    addq     %{2s}, %{1s}
            \\    movq     %{1s}, {0s}
            \\
            , .{
                try self.stackStr(node.symbol),
                @tagName(load_reg),
                @tagName(expr_reg),
            }
        ),

        .@"-=" => try writer.print(
            \\    movq     {0s}, %{1s}
            \\    subq     %{2s}, %{1s}
            \\    movq     %{1s}, {0s}
            \\
            , .{
                try self.stackStr(node.symbol),
                @tagName(load_reg),
                @tagName(expr_reg),
            }
        ),

        .@"*=" => try writer.print(
            \\    movq     {0s}, %rax
            \\    imulq    %{1s}
            \\    movq     %rax, %{0s}
            \\
            , .{
                try self.stackStr(node.symbol),
                @tagName(expr_reg),
            }
        ),

        .@"/=" => try writer.print(
            \\    xorq     %rdx, %rdx
            \\    movq     {0s}, %rax
            \\    cqo
            \\    idivq    %{1s}
            \\    movq     %rax, {0s}
            \\
            , .{
                try self.stackStr(node.symbol),
                @tagName(expr_reg),
            }
        ),

        .@"%=" => try writer.print(
            \\    xorq     %rdx, %rdx
            \\    movq     {0s}, %rax
            \\    cqo
            \\    idivq    %{1s}
            \\    movq     %rdx, {0s}
            \\
            , .{
                try self.stackStr(node.symbol),
                @tagName(expr_reg),
            }
        ),

        else => unreachable, // illegal assignment operator
    }

    return .none;
}

fn binary(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    return switch (node.operator.kind) {
        .@"-",
        .@"+",
        .@"*",
        .@"/",
        .@"%" => self.arithmetic(node, writer),

        .@"<",
        .@"<=",
        .@"==",
        .@">",
        .@">=",
        .@"!=" => self.comparison(node, writer),

        .@"and",
        .@"or" => self.logical(node, writer),

        else => unreachable, // illegal binary operator
    };
}

fn logical(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const left = try self.generateNode(node.left, writer);
    const right = try self.generateNode(node.right, writer);

    const result = left;
    const discard = right;

    defer self.pool.free(discard);

    switch (node.operator.kind) {

        .@"and" => try writer.print(
            \\    andq     %{1s}, %{0s}
            \\
            , .{ @tagName(left), @tagName(right), }
        ),

        .@"or" => try writer.print(
            \\    orq      %{1s}, %{0s}
            \\
            , .{ @tagName(left), @tagName(right), }
        ),

        else => unreachable, // illegal logical operator
    }

    return result;
}

fn arithmetic(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const left = try self.generateNode(node.left, writer);
    const right = try self.generateNode(node.right, writer);

    const result = left;
    const discard = right;

    defer self.pool.free(discard);

    switch (node.operator.kind) {

        .@"+" => try writer.print(
            \\    addq     %{0s}, %{1s}
            \\
            , .{ @tagName(right), @tagName(left), }
        ),

        .@"-" => try writer.print(
            \\    subq     %{0s}, %{1s}
            \\
            , .{ @tagName(right), @tagName(left), }
        ),

        .@"*" => try writer.print(
            \\    movq     %{0s}, %rax
            \\    imulq    %{1s}
            \\    movq     %rax, %{0s}
            \\
            , .{ @tagName(left), @tagName(right), }
        ),

        .@"/" => try writer.print(
            \\    xorq     %rdx, %rdx
            \\    movq     %{0s}, %rax
            \\    cqo
            \\    idivq    %{1s}
            \\    movq     %rax, %{0s}
            \\
            , .{ @tagName(left), @tagName(right), }
        ),

        .@"%" => try writer.print(
            \\    xorq     %rdx, %rdx
            \\    movq     %{0s}, %rax
            \\    cqo
            \\    idivq    %{1s}
            \\    movq     %rdx, %{0s}
            \\
            , .{ @tagName(left), @tagName(right), }
        ),

        else => unreachable, // illegal arithmetic operator
    }

    return result;
}

fn comparison(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const left = try self.generateNode(node.left, writer);
    const right = try self.generateNode(node.right, writer);

    const result = left;
    const discard = right;

    defer self.pool.free(discard);

    const jump_instruction = switch (node.operator.kind) {
        .@"<"  => "jl  ",
        .@"<=" => "jle ",
        .@"==" => "je  ",
        .@">"  => "jg  ",
        .@">=" => "jge ",
        .@"!=" => "jne ",
        else   => unreachable, // illegal comparison operator
    };

    const true_label = self.newLabel();
    const done_label = self.newLabel();

    try writer.print(
        \\    cmpq     %{1s}, %{0s}
        \\    {2s}     .true_{3d}
        \\    movq     $0, %{0s}
        \\    jmp      .done_{4d}
        \\.true_{3d}:
        \\    movq     $1, %{0s}
        \\.done_{4d}:
        \\
        , .{
            @tagName(left),
            @tagName(right),
            jump_instruction,
            true_label,
            done_label,
        }
    );

    return result;
}

fn unary(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const operand = try self.generateNode(node.operand, writer);

    switch (node.operator.kind) {

        .@"-" => try writer.print(
            \\    negq     %{0s}
            \\
            , .{ @tagName(operand), }
        ),

        .@"!" => try writer.print(
            \\    xorq     $1, %{0s}
            \\
            , .{ @tagName(operand), }
        ),

        else => unreachable, // illegal unary operator
    }

    return operand;
}

fn call(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    self.current_arg = 0;
    if (node.args) |args| {
        _ = try self.generateNode(args, writer);
    }

    // pop possibly clobbered rdx
    if (self.current_arg >= 3) {
        try writer.print(
            \\    pop      %rdx
            \\
            , .{}
        );
    }

    try callerSave(writer);
    try writer.print(
        \\    call     {0s}
        \\
        , .{ node.name.where, }
    );
    try callerRestore(writer);

    const result = try self.pool.alloc();

    try writer.print(
        \\    movq     %rax, %{0s}
        \\
        , .{ @tagName(result), }
    );

    return result;
}

fn argumentList(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const expr = try self.generateNode(node.expr, writer);
    defer self.pool.free(expr);

    const arg_reg: ArgumentRegister
        = @enumFromInt(self.current_arg);

    self.current_arg += 1;

    try writer.print(
        \\    movq     %{0s}, %{1s}
        \\
        , .{ @tagName(expr), @tagName(arg_reg), }
    );

    // rdx may be clobbered
    if (arg_reg == .rdx) {
        try writer.print(
            \\    push     %rdx
            \\
            , .{}
        );
    }

    if (node.next) |next| {
        _ = try self.generateNode(next, writer);
    }

    return .none;
}

fn block(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    return self.generateNode(node.content, writer);
}

fn statementList(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    _ = self.generateNode(node.statement, writer) catch |e| {
        // Codegen errors are recoverable
        if (e != error.CodeGenError) {
            return e;
        }
    };

    if (node.next) |next| {
        _ = try self.generateNode(next, writer);
    }

    return .none;
}

fn ifStatement(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const done_label = self.newLabel();
    const condition = try self.generateNode(node.condition, writer);
    defer self.pool.free(condition);

    try writer.print(
        \\    cmpq     $1, %{s}
        \\
        , .{ @tagName(condition), }
    );

    if (node.else_block) |else_block| {

        const else_label = self.newLabel();

        try writer.print(
            \\    jne      .else_{0d}
            \\
            , .{ else_label, }
        );

        _ = try self.generateNode(node.block, writer);

        try writer.print(
            \\    jmp      .done_{1d}
            \\.else_{0d}:
            \\
            , .{ else_label, done_label, }
        );

        _ = try self.generateNode(else_block, writer);

    } else {

        try writer.print(
            \\    jne      .done_{0d}
            \\
            , .{ done_label, }
        );

        _ = try self.generateNode(node.block, writer);
    }

    try writer.print(
        \\.done_{0d}:
        \\
        , .{ done_label, }
    );

    return .none;
}

fn whileStatement(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const continue_label = self.newLabel();
    const break_label = self.newLabel();

    try self.loop_stack.append(.{
        .continue_label = continue_label,
        .break_label = break_label,
    });

    try writer.print(
        \\.continue_{0d}:
        \\
        , .{ continue_label, }
    );

    const condition = try self.generateNode(node.condition, writer);
    defer self.pool.free(condition);

    try writer.print(
        \\    cmpq     $1, %{0s}
        \\    jne      .break_{1d}
        \\
        , .{ @tagName(condition), break_label, }
    );

    _ = try self.generateNode(node.block, writer);

    try writer.print(
        \\    jmp      .continue_{0d}
        \\.break_{1d}:
        \\
        , .{ continue_label, break_label, }
    );

    _ = self.loop_stack.popOrNull();

    return .none;
}

fn printStatement(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const expr = try self.generateNode(node.expr, writer);
    defer self.pool.free(expr);

    try writer.print(
        \\    leaq     __fmt(%rip), %rdi
        \\    movq     %{0s}, %rsi
        \\    movq     $0, %rax
        \\    call     printf
        \\
        , .{
            @tagName(expr),
        }
    );

    return .none;
}

fn variable(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const register = try self.pool.alloc();
    try writer.print(
        \\    movq     {0s}, %{1s}
        \\
        , .{
            try self.stackStr(node.symbol),
            @tagName(register),
        }
    );

    return register;
}

fn constant(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const register = try self.pool.alloc();
    try writer.print(
        \\    movq     ${0d}, %{1s}
        \\
        , .{ node.value, @tagName(register), }
    );

    return register;
}

fn callerSave(writer: anytype) anyerror!void {

    try writer.print(
        \\    push     %r8
        \\    push     %r9
        \\    push     %r10
        \\    push     %r11
        \\
        , .{}
    );
}

fn callerRestore(writer: anytype) anyerror!void {

    try writer.print(
        \\    pop      %r11
        \\    pop      %r10
        \\    pop      %r9
        \\    pop      %r8
        \\
        , .{}
    );
}

fn calleeBegin(self: *Self, writer: anytype) anyerror!void {

    try writer.print(
        \\    push     %rbp
        \\    subq     ${0d}, %rsp
        \\    movq     %rsp, %rbp
        \\    push     %r12
        \\    push     %r13
        \\    push     %r14
        \\    push     %r15
        \\
        , .{ self.current_space, }
    );
}

fn calleeEnd(self: *Self, writer: anytype) anyerror!void {

    try writer.print(
        \\    pop      %r15
        \\    pop      %r14
        \\    pop      %r13
        \\    pop      %r12
        \\    addq     ${0d}, %rsp
        \\    pop      %rbp
        \\
        , .{ self.current_space, }
    );
}

fn spillParams(count: usize, writer: anytype) anyerror!void {

    for (std.enums.values(ArgumentRegister), 0..) |reg, i| {

        if (i == count) break;

        const offset = stackOffset(i);
        try writer.print(
           \\    movq     %{0s}, {1d}(%rbp)
           \\
           , .{ @tagName(reg), offset, }
        );
    }
}
fn returnStatement(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const expr_reg = try self.generateNode(node.expr, writer);
    defer self.pool.free(expr_reg);
    try writer.print(
        \\    movq     %{0s}, %rax
        \\
        , .{ @tagName(expr_reg), }
    );


    try self.calleeEnd(writer);

    try writer.print(
        \\    ret
        \\
        , .{}
    );

    return .none;
}
