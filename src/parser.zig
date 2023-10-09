
const std = @import("std");

const TokenKind   = @import("token.zig").TokenKind;
const Token       = @import("token.zig").Token;
const ast         = @import("ast.zig");
const TokenStream = @import("lexer.zig").TokenStream;

pub const Error = struct {

    location: ?[]const u8,
    kind: union(enum) {
        expected_token: TokenKind,
        expected_token_range: []const TokenKind,
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

        return try self.statement_list();     
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
            .location = if (next) |n| n.loc else null,
            .kind = .{
                .expected_token = kind,
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
            .location = if (next) |n| n.loc else null,
            .kind = .{
                .expected_token_range = range,
            },
        });

        unreachable;
    }

    fn sync(self: *Self, kind: TokenKind) !void {
        
        while (self.stream.next()) |next| {
            if (next.kind == kind) {
                return;
            }
        }

        return error.Sync;
    }

    fn statement_list(self: *Self) !usize {
        
        const first = if (self.stream.peek()) |_| try self.statement()
            else {
                try self.pushError(.{
                    .location = null,
                    .kind = .unexpected_eoi,
                });
                unreachable;
        };

        // More statements?
        if (self.stream.peek()) |_| {

            const follow = try self.statement_list();
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
                .let_kw,
                .identifier,
                .if_kw,
                .while_kw,
            }
        );

        // Putback token
        self.stream.back() catch unreachable;

        const stmt = switch (first.kind) {

            .let_kw     => self.declaration(),
            .identifier => self.assignment(),
            // TODO
            .if_kw      => unreachable, //self.if_statement(),
            .while_kw   => unreachable, //self.while_statement(),
            else => unreachable,

        } catch {

            // If we encounter an error during parsing of a single statement
            //  we skip to the next statement
            try self.sync(.semi);
            return self.statement();
        };

        _ = try self.expect(.semi);
        return stmt;
    }

    pub fn declaration(self: *Self) !usize {


        // Consume let keyword
        _ = self.stream.next();

        // <declaration> ::= "let" "identifier" "=" <expression>
        const left = try self.expect(.identifier);
        _ = try self.expect(.assign);
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
                .assign,
                .plus_eq,
                .minus_eq,
                .mul_eq,
                .div_eq
            }
        );
        const right = try self.expression();

        return self.pushNode(.{
            .assignment = .{
                .identifier = left,
                .operator = operator,
                .expression = right,
            },
        });
    }

    pub fn expression(self: *Self) anyerror!usize {

        // Lowest precedence is comparison
        const left = try self.sum();
        const operator = if (self.stream.peek()) |peek| block: {
            switch (peek.kind) {

                // <expression> ::= <sum> ("==" | ">=" | "<=" | "!=") <expression>
                .equal,
                .geq,
                .leq,
                .neq => {
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
                .plus,
                .minus => {
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
                .lpar,
                .identifier,
                .literal,
                .minus,
                .not,
            }        
        );

        switch (left.kind) {

            // <factor> ::= "(" <expression> ")"
            .lpar => {
                const inner = try self.expression();
                _ = try self.expect(.rpar);
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

                        .mul,
                        .div => {
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
            .minus, .not => {
                
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
};
