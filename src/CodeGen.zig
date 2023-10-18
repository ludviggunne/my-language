
const std          = @import("std");
const Self         = @This();
const Ast          = @import("Ast.zig");
const RegisterPool = @import("RegisterPool.zig");
const Register     = RegisterPool.Register;
const SymbolTable  = @import("SymbolTable.zig");
const Error        = @import("Error.zig");

const ParamRegs = enum {
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
current_func:   struct {
    returns: bool = false,
    is_main: bool = false,
},

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
        .current_func  = .{},
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

fn evictAll(self: *Self, writer: anytype) anyerror!void {

    for (&self.pool.registers, 0..) |*state, i| {
        switch (state.*) {
            .unused => continue,
            .result => unreachable, // can't evict result
            .symbol => |v| {
                const register: Register = @enumFromInt(i);
                try writer.print(
                    \\    movq     %{0s}, {1s} // evict {2s}
                    \\
                    , .{
                        @tagName(register),
                        try self.stackStr(v),
                        self.symtab.symbols.items[v].name,
                    }
                );
                state.* = .unused;
            },
        }
    }
}

fn alloc(self: *Self, symbol: ?usize, writer: anytype) anyerror!Register {

    const allocation = try self.pool.alloc(symbol);
    if (allocation.spilled) |spilled| {
        try writer.print(
            \\    movq     %{0s}, {1s} // evict {2s}
            \\
            , .{
                @tagName(allocation.register),
                try self.stackStr(spilled),
                self.symtab.symbols.items[symbol.?].name,
            }
        );
    }
    if (allocation.load and symbol != null) {
        try writer.print(
            \\    movq     {0s}, %{1s} // load {2s}
            \\
            , .{
                try self.stackStr(symbol.?),
                @tagName(allocation.register),
                self.symtab.symbols.items[symbol.?].name,
            }
        );
    }
    return allocation.register;
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

    const offset: i64 = -8 * @as(i64, @intCast(stack_id + 1));

    return std.fmt.bufPrint(&static.buf, "{d}(%rbp)", .{ offset, });
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
    
    // TODO: implement

    try writer.print(
        \\{0s}:
        \\    pushq    %rbp
        \\    movq     %rsp, %rbp
        \\
        , .{ node.name.where, });

    _ = try self.generateNode(node.body, writer);

    try writer.print(
        \\    movq     $60, %rax
        \\    movq     $0, %rdi
        \\    syscall
        \\
        , .{}
    );

    return .none;
}

fn parameterList(self: *Self, node: anytype, writer: anytype) anyerror!Register {
   _ = .{ self, node, writer, };
   unreachable;
}

fn declaration(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const register = try self.alloc(node.symbol, writer);
    const expr_reg = try self.generateNode(node.expr, writer);
    defer self.pool.freeIfResult(expr_reg);

    try writer.print(
        \\    movq     %{0s}, %{1s}
        \\
        , .{ @tagName(expr_reg), @tagName(register), }
    );

    return register;
}

fn assignment(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const register = try self.alloc(node.symbol, writer);
    const expr_reg = try self.generateNode(node.expr, writer);
    defer self.pool.freeIfResult(expr_reg);

    switch (node.operator.kind) {

        .@"=" => try writer.print(
            \\    movq     %{0s}, %{1s}
            \\
            , .{ @tagName(expr_reg), @tagName(register), }
        ),

        .@"+=" => try writer.print(
            \\    addq     %{0s}, %{1s}
            \\
            , .{ @tagName(expr_reg), @tagName(register), }
        ),

        .@"-=" => try writer.print(
            \\    subq     %{0s}, %{1s}
            \\
            , .{ @tagName(expr_reg), @tagName(register), }
        ),
        
        .@"*=" => try writer.print(
            \\    movq     %{0s}, %rax
            \\    imulq    %{1s}
            \\    movq     %rax, %{1s}
            \\
            , .{ @tagName(expr_reg), @tagName(register), }
        ),

        .@"/=" => try writer.print(
            \\    xorq     %rdx, %rdx
            \\    movq     %{1s}, %rax
            \\    cqo
            \\    idivq    %{0s}
            \\    movq     %rax, %{1s}
            \\
            , .{ @tagName(expr_reg), @tagName(register), }
        ),

        .@"%=" => try writer.print(
            \\    xorq     %rdx, %rdx
            \\    movq     %{1s}, %rax
            \\    cqo
            \\    idivq    %{0s}
            \\    movq     %rdx, %{1s}
            \\
            , .{ @tagName(expr_reg), @tagName(register), }
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

        else => unreachable, // illegal binary operator
    };
}

fn arithmetic(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const left = try self.generateNode(node.left, writer);
    const right = try self.generateNode(node.right, writer);

    // If either of operands are non-variables, we can reuse
    const result = if (self.pool.isResult(left)) left
        else if (self.pool.isResult(right)) right
            else try self.alloc(null, writer);

    if (result != left) self.pool.freeIfResult(left);
    if (result != right) self.pool.freeIfResult(right);

    switch (node.operator.kind) {

        .@"+" => try writer.print(
            \\    movq     %{1s}, %{0s}
            \\    addq     %{2s}, %{0s}
            \\
            , .{ @tagName(result), @tagName(left), @tagName(right), }
        ),

        .@"-" => try writer.print(
            \\    movq     %{1s}, %{0s}
            \\    subq     %{2s}, %{0s}
            \\
            , .{ @tagName(result), @tagName(left), @tagName(right), }
        ),

        .@"*" => try writer.print(
            \\    movq     %{0s}, %rax
            \\    imulq    %{1s}
            \\    movq     %rax, %{2s}
            \\
            , .{ @tagName(left), @tagName(right), @tagName(result), }
        ),

        .@"/" => try writer.print(
            \\    xorq     %rdx, %rdx
            \\    movq     %{0s}, %rax
            \\    cqo
            \\    idivq    %{1s}
            \\    movq     %rax, %{2s}
            \\
            , .{ @tagName(left), @tagName(right), @tagName(result), }
        ),

        .@"%" => try writer.print(
            \\    xorq     %rdx, %rdx
            \\    movq     %{0s}, %rax
            \\    cqo
            \\    idivq    %{1s}
            \\    movq     %rdx, %{2s}
            \\
            , .{ @tagName(left), @tagName(right), @tagName(result), }
        ),

        else => unreachable, // illegal arithmetic operator
    }

    return result;
}

fn comparison(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const left = try self.generateNode(node.left, writer);
    const right = try self.generateNode(node.right, writer);
    
    const result = if (self.pool.isResult(left)) left
        else if (self.pool.isResult(right)) right
            else try self.alloc(null, writer);

    if (result != left) self.pool.freeIfResult(left);
    if (result != right) self.pool.freeIfResult(right);
    
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
        \\    {3s}     .true_{4d}
        \\    movq     $0, %{2s}
        \\    jmp      .done_{5d}
        \\.true_{4d}:
        \\    movq     $1, %{2s}
        \\.done_{5d}:
        \\
        , .{
            @tagName(left),
            @tagName(right),
            @tagName(result),
            jump_instruction,
            true_label,
            done_label,
        }
    );

    return result;
}

fn unary(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const operand = try self.generateNode(node.operand, writer);
    const result = if (self.pool.isResult(operand)) operand
        else try self.alloc(null, writer);

    if (operand != result) self.pool.freeIfResult(operand);

    switch (node.operator.kind) {
        
        .@"-" => try writer.print(
            \\    movq     %{0s}, %{1s}
            \\    negq     %{1s}
            \\
            , .{ @tagName(operand), @tagName(result), }
        ),

        .@"!" => try writer.print(
            \\    movq     %{0s}, %{1s}
            \\    xorq     $1, %{1s}
            \\
            , .{ @tagName(operand), @tagName(result), }
        ),

        else => unreachable, // illegal unary operator
    }

    return operand;
}

fn call(self: *Self, node: anytype, writer: anytype) anyerror!Register {
   _ = .{ self, node, writer, };
   unreachable;
}

fn argumentList(self: *Self, node: anytype, writer: anytype) anyerror!Register {
   _ = .{ self, node, writer, };
   unreachable;
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

    try writer.print(
        \\    cmpq     $1, %{s}
        \\
        , .{ @tagName(condition), }
    );

    self.pool.free(condition);

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

    // We need to reset register state
    //  because it may be fucked up by block
    try self.evictAll(writer);

    try writer.print(
        \\.continue_{0d}:
        \\
        , .{ continue_label, }
    );

    const condition = try self.generateNode(node.condition, writer);
    // Free condition register so it's not used up in block
    self.pool.freeIfResult(condition);

    try self.evictAll(writer);

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

    try self.evictAll(writer);

    _ = self.loop_stack.popOrNull();

    return .none;
}

fn returnStatement(self: *Self, node: anytype, writer: anytype) anyerror!Register {
   _ = .{ self, node, writer, };
   unreachable;
}

fn printStatement(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    const expr = try self.generateNode(node.expr, writer);
    self.pool.freeIfResult(expr);

    try writer.print(
        \\    push     %r8
        \\    push     %r9
        \\    push     %r10
        \\    push     %r11
        \\    push     %rbp
        \\    leaq     __fmt(%rip), %rdi
        \\    movq     %{0s}, %rsi
        \\    movq     $0, %rax
        \\    call     printf
        \\    pop      %rbp
        \\    pop      %r11
        \\    pop      %r10
        \\    pop      %r9
        \\    pop      %r8
        \\
        , .{
            @tagName(expr),
        }
    );

    return .none;
}

fn variable(self: *Self, node: anytype, writer: anytype) anyerror!Register {

    return try self.alloc(node.symbol, writer);
}

fn constant(self: *Self, node: anytype, writer: anytype) anyerror!Register {
    
    const register = try self.alloc(null, writer);
    try writer.print(
        \\    movq     ${0d}, %{1s}
        \\
        , .{ node.value, @tagName(register), }
    );

    return register;
}
