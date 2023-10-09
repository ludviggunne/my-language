
const std = @import("std");

const TokenKind   = @import("token.zig").TokenKind;
const Token       = @import("token.zig").Token;
const ast         = @import("ast.zig");
const TokenStream = @import("lexer.zig").TokenStream;

pub const Error = struct {

    begin: ?usize,
    end:   ?usize,
    kind: union(enum) {
        expected_token: struct {
            expected: TokenKind,
            found:    ?TokenKind,
        },
        expected_token_range: struct {
            expected: []const TokenKind,
            found: ?TokenKind
        },
        unexpected_eoi,
    },
};

pub const Parser = struct {

    const Self = @This();

    nodes: std.ArrayList(ast.Node),
    errors: std.ArrayList(Error),
    stream: *TokenStream,

    pub fn init(allocator: std.mem.Allocator, stream: *TokenStream) Self {
        
        return .{
            .nodes = std.ArrayList(ast.Node).init(allocator),
            .errors = std.ArrayList(Error).init(allocator),
            .stream = stream,
        };
    }

    pub fn parse(self: *Self) !usize {

        return try self.statement_list(false); // not block
    }

    fn pushError(self: *Self, err: Error) !void {

        try self.errors.append(err);
        return error.PushError;
    }

    fn pushNode(self: *Self, node: ast.Node) !usize {

        try self.nodes.append(node);
        return self.nodes.items.len - 1;
    }

    fn expect(self: *Self, kind: TokenKind) !Token {

        const next = self.stream.next();

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

    fn expectRange(self: *Self, comptime range: []const TokenKind) !Token {

        const next = self.stream.next();

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

    // TODO: Add sync for multiple tokens 
    fn sync(self: *Self, kind: TokenKind) !void {
        
        while (self.stream.next()) |next| {
            if (next.kind == kind) {
                return;
            }
        }

        return error.Sync;
    }

    fn statement_list(self: *Self, comptime is_block: bool) anyerror!usize {
        
        const first = if (self.stream.peek()) |_| try self.statement()
            else {
                try self.pushError(.{
                    .begin = null,
                    .end   = null,
                    .kind = .unexpected_eoi,
                });
                unreachable;
        };

        // More statements?
        if (self.stream.peek()) |peek| {

            // If we're in a block, don't get upset about right brace
            //  just return the previous statement
            if (is_block and peek.kind == .@"}") {
                return first;
            }

            const follow = try self.statement_list(is_block);
            return self.pushNode(.{
                .statement_list = .{
                    .first = first,
                    .follow = follow,
                },
            });
        } else return first;
    }

    fn statement(self: *Self) !usize {

        const first = try self.expectRange(
            &[_] TokenKind {
                .@"let",
                .identifier,
                .@"if",
                .@"while",
                .@"{",
            }
        );

        // Putback token
        self.stream.back() catch unreachable;
        
        var expect_semi = true;
        const stmt = switch (first.kind) {

            .@"let" => self.declaration(),
            .identifier => self.assignment(),

            .@"if" => blk: {
                expect_semi = false;
                break :blk self.if_statement();
            },
            .@"while" => blk: {
                expect_semi = false;
                break :blk self.while_statement();
            },
            .@"{" => blk: {
                expect_semi = false;
                break :blk self.block();
            },
            else => unreachable,

        } catch {

            // If we encounter an error during parsing of a single statement
            //  we skip to the next statement
            try self.sync(.@";");
            return self.statement();
        };

        // Expect ; only from certain statements
        if (expect_semi) {
            _ = try self.expect(.@";");
        }
        return stmt;
    }

    pub fn declaration(self: *Self) !usize {

        // Consume let keyword
        _ = self.stream.next();

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
        const left = self.stream.next().?;
        const operator = try self.expectRange(
            &[_]TokenKind {
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
        const operator = if (self.stream.peek()) |peek| block: {
            switch (peek.kind) {

                // <expression> ::= <sum> ("==" | ">" | ">=" | "<" | "<=" | "!=") <expression>
                .@"==",
                .@">",
                .@">=",
                .@"<",
                .@"<=",
                .@"!=" => {
                    // Consume peeked
                    _ = self.stream.next();
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
        const operator = if (self.stream.peek()) |peek| block: {
            switch (peek.kind) {

                // <sum> ::= <factor> ("+" | "-") <sum>
                .@"+",
                .@"-" => {
                    // Consume peeked
                    _ = self.stream.next();
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
            &[_] TokenKind {
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
                
                if (self.stream.peek()) |peek| {

                    switch (peek.kind) {

                        .@"*",
                        .@"/" => {
                            const operator = self.stream.next().?;
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

    fn block(self: *Self) !usize {

        _ = try self.expect(.@"{");
        const content = try self.statement_list(true);
        _ = try self.expect(.@"}");

        return self.pushNode(.{
            .block = .{
                .content = content,
            },
        });
    }

    fn if_statement(self: *Self) !usize {
        
        // consume if keyword
        _ = self.stream.next();
        
        const condition = try self.expression();
        const blk = try self.block();
        
        return self.pushNode(.{
            .if_statement = .{
                .condition = condition,
                .block     = blk,
            },
        });
    }

    fn while_statement(self: *Self) !usize {
        
        // consume while keyword
        _ = self.stream.next();
        
        const condition = try self.expression();
        const blk = try self.block();
        
        return self.pushNode(.{
            .while_statement = .{
                .condition = condition,
                .block     = blk,
            },
        });
    }
};
