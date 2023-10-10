
const std = @import("std");

const Token = @import("Token.zig");
const Lexer = @import("Lexer.zig");
const ast   = @import("ast.zig");

pub const Error = struct {

    begin: ?usize,
    end:   ?usize,
    kind: union(enum) {
        expected_token: struct {
            expected: Token.Kind,
            found:    ?Token.Kind,
        },
        expected_token_range: struct {
            expected: []const Token.Kind,
            found: ?Token.Kind
        },
        unexpected_eoi,
    },
};

const Self = @This();

nodes: std.ArrayList(ast.Node),
errors: std.ArrayList(Error),
lexer: *Lexer,

pub fn init(allocator: std.mem.Allocator, lexer: *Lexer) Self {
    
    return .{
        .nodes = std.ArrayList(ast.Node).init(allocator),
        .errors = std.ArrayList(Error).init(allocator),
        .lexer = lexer,
    };
}

pub fn deinit(self: *Self) void {

    self.nodes.deinit();
    self.errors.deinit();
}

pub fn parse(self: *Self) !ast.Ast {

    const result = try self.statementList(false); // not block
    return if (self.errors.items.len > 0) 
        error.SomeError 
    else .{
        .root  = result,
        .nodes = self.nodes.items,
    };
}

fn pushError(self: *Self, err: Error) !void {

    try self.errors.append(err);
    return error.PushError;
}

fn pushNode(self: *Self, node: ast.Node) !usize {

    try self.nodes.append(node);
    return self.nodes.items.len - 1;
}

fn expect(self: *Self, kind: Token.Kind) !Token {

    const next = self.lexer.next();

    if (next) |token| {
        if (token.kind == kind) {
            return token;
        }
    }

    try self.pushError(.{
        .begin = if (next) |n| n.begin else null,
        .end = if (next) |n| n.end else null,
        .kind = .{
            .expected_token = .{
                .expected = kind,
                .found = if (next) |n| n.kind else null,
            },
        },
    });

    unreachable;
}

fn expectRange(self: *Self, comptime range: []const Token.Kind) !Token {

    const next = self.lexer.next();

    if (next) |token| {
        for (range) |expected| {
            if (token.kind == expected) {
                return token;
            }
        }
    }

    try self.pushError(.{
        .begin = if (next) |n| n.begin else null,
        .end   = if (next) |n| n.end else null,
        .kind = .{
            .expected_token_range = .{
                .expected = range,
                .found = if (next) |n| n.kind else null,
            },
        },
    });

    unreachable;
}

fn expectRangeNoNext(self: *Self, comptime range: []const Token.Kind) !Token {

    const peek = self.lexer.peek();

    if (peek) |token| {
        for (range) |expected| {
            if (token.kind == expected) {
                return token;
            }
        }
    }

    try self.pushError(.{
        .begin = if (peek) |p| p.begin else null,
        .end   = if (peek) |p| p.end else null,
        .kind = .{
            .expected_token_range = .{
                .expected = range,
                .found = if (peek) |p| p.kind else null,
            },
        },
    });

    unreachable;
}

fn sync(self: *Self) void {
    
    // Skip til ;
    while (self.lexer.next()) |next| {
        if (next.kind == .@";") {
            break;
        }
    }

    // Skip following }
    while (self.lexer.peek()) |peek| {
        if (peek.kind != .@"}") {
            break;   
        }

        _ = self.lexer.next();
    }
}

fn statementList(self: *Self, comptime is_block: bool) anyerror!usize {

    const first = if (self.lexer.peek()) |_| try self.statement()
        else return self.pushNode(.empty);

    // More statements?
    if (self.lexer.peek()) |peek| {

        // If we're in a block, don't get upset about right brace
        //  just return the previous statement
        if (is_block and peek.kind == .@"}") {
            return first;
        }

        const follow = try self.statementList(is_block);
        return self.pushNode(.{
            .statement_list = .{
                .first = first,
                .follow = follow,
            },
        });
    } else return first;
}

fn statement(self: *Self) !usize {

    if (self.lexer.peek() == null) {
        return self.pushNode(.empty);
    }

    // Expect without consuming
    const first = try self.expectRangeNoNext(
        &[_] Token.Kind {
            .@"let",
            .identifier,
            .@"print",
            .@"if",
            .@"while",
            .@"{",
        }
    );
    
    var expect_semi = true;
    const stmt = switch (first.kind) {

        .@"let"     => self.declaration(),
        .identifier => self.assignment(),
        .@"print"   => self.printStatement(),

        .@"if" => blk: {
            expect_semi = false;
            break :blk self.ifStatement();
        },
        .@"while" => blk: {
            expect_semi = false;
            break :blk self.whileStatement();
        },
        .@"{" => blk: {
            expect_semi = false;
            break :blk self.block();
        },
        else => unreachable,

    } catch {

        // If we encounter an error during parsing of a single statement
        //  we skip to the next statement
        self.sync();
        return try self.statement();
    };

    // Expect ; only from certain statements
    if (expect_semi) {
        _ = try self.expect(.@";");
    }
    return stmt;
}

pub fn declaration(self: *Self) !usize {

    // Consume let keyword
    _ = self.lexer.next();

    // <declaration> ::= "let" "identifier" "=" <expression>
    const left = try self.expect(.identifier);
    _ = try self.expect(.@"=");
    const right = try self.expression();

    return self.pushNode(.{ 
        .declaration = .{
            .identifier = left,
            .expression = right,
        }
    });
}

pub fn assignment(self: *Self) !usize {

    // <assignment> ::= <identifier> ("=" | "+=" | "-=" | "*=" | "/=" )  
    const left = self.lexer.next().?;
    const operator = try self.expectRange(
        &[_]Token.Kind {
            .@"=",
            .@"+=",
            .@"-=",
            .@"*=",
            .@"/=",
        }
    );
    const right = try self.expression();

    return self.pushNode(.{
        .assignment = .{
            .identifier = left,
            .operator   = operator,
            .expression = right,
        },
    });
}

pub fn expression(self: *Self) anyerror!usize {

    // Lowest precedence is comparison
    const left = try self.sum();
    const operator = if (self.lexer.peek()) |peek| block: {
        switch (peek.kind) {

            // <expression> ::= <sum> ("==" | ">" | ">=" | "<" | "<=" | "!=") <expression>
            .@"==",
            .@">",
            .@">=",
            .@"<",
            .@"<=",
            .@"!=" => {
                // Consume peeked
                _ = self.lexer.next();
                break :block peek;
            },

            // No comparison, return only "left" hand
            else => return left,
        }
    } else return left;

    const right = try self.expression();

    return self.pushNode(.{
        .binary = .{
            .left = left,
            .operator = operator,
            .right = right,
        },
    });
}

pub fn sum(self: *Self) !usize {

    const left = try self.factor();
    const operator = if (self.lexer.peek()) |peek| block: {
        switch (peek.kind) {

            // <sum> ::= <factor> ("+" | "-") <sum>
            .@"+",
            .@"-" => {
                // Consume peeked
                _ = self.lexer.next();
                break :block peek;
            },

            // <sum> ::= <factor>
            else => return left,
        }
    } else return left;

    const right = try self.sum();

    return self.pushNode(.{
        .binary = .{
            .left = left,
            .operator = operator,
            .right = right,
        },
    });
}

pub fn factor(self: *Self) !usize {

    // Factor must begin with one of these tokens
    const left = try self.expectRange(
        &[_] Token.Kind {
            .@"(",
            .identifier,
            .literal,
            .@"-",
            .@"!",
        }        
    );

    switch (left.kind) {

        // <factor> ::= "(" <expression> ")"
        .@"(" => {
            const inner = try self.expression();
            _ = try self.expect(.@")");
            return inner;
        },
        
        // <factor> ::= (<identifier> | <literal>) ("*" | "/")
        .identifier, .literal => {

            const left_node = try self.pushNode(.{
                .atomic = .{
                    .token = left,
                },
            });
            
            if (self.lexer.peek()) |peek| {

                switch (peek.kind) {

                    .@"*",
                    .@"/" => {
                        const operator = self.lexer.next().?;
                        const right = try self.factor();

                        return self.pushNode(.{
                            .binary = .{
                                .left = left_node,
                                .operator = operator,
                                .right = right,
                            },
                        });
                    },

                    // No additional factors
                    else => return left_node,
                }
            } else return left_node;
        },

        // <factor> ::= "-" <factor>
        .@"-", .@"!" => {
            
            const operand = try self.factor();
            return self.pushNode(.{
                .unary = .{
                    .operator = left,
                    .operand = operand,
                },
            });
        },

        // Already asserted left is one of these ^^^  
        else => unreachable,
    }
}

fn printStatement(self: *Self) !usize {

    _ = try self.expect(.@"print");
    const argument = try self.expression();

    return self.pushNode(.{
        .print_statement = .{
            .argument = argument,
        },
    });
}

// TODO: Empty block
fn block(self: *Self) !usize {

    _ = try self.expect(.@"{");
    const content = try self.statementList(true);
    _ = try self.expect(.@"}");

    return self.pushNode(.{
        .block = .{
            .content = content,
        },
    });
}

fn ifStatement(self: *Self) !usize {
    
    // consume if keyword
    _ = self.lexer.next();
    
    const condition = try self.expression();
    const blk = try self.block();
    
    return self.pushNode(.{
        .if_statement = .{
            .condition = condition,
            .block     = blk,
        },
    });
}

fn whileStatement(self: *Self) !usize {
    
    // consume while keyword
    _ = self.lexer.next();
    
    const condition = try self.expression();
    const blk = try self.block();
    
    return self.pushNode(.{
        .while_statement = .{
            .condition = condition,
            .block     = blk,
        },
    });
}
