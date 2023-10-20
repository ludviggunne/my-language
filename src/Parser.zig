
// TODO: sync toplevel statements

const std = @import("std");

const Self = @This();

const Ast   = @import("Ast.zig");
const Lexer = @import("Lexer.zig");
const Token = @import("Token.zig");
const Error = @import("Error.zig");
const Type  = @import("types.zig").Type;

const Action = enum {
    take,
    peek,
};

const SyncResult = enum {
    empty,
    statement,
};

lexer: *Lexer,
ast:   *Ast,
errors: std.ArrayList(Error),

pub fn init(lexer: *Lexer, ast: *Ast, allocator: std.mem.Allocator) Self {

    return .{
        .lexer = lexer,
        .ast = ast,
        .errors = std.ArrayList(Error).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.errors.deinit();
}

pub fn parse(self: *Self) !void {

    self.ast.root = try self.topLevelList();
    if (self.errors.items.len > 0) {
        return error.ParseError;
    }
}

fn pushError(self: *Self, err: Error) !void {
    
   try self.errors.append(err); 
   return error.ParseError;
}

fn sync(self: *Self) !SyncResult {

    while (try self.lexer.peek()) |token| {

        switch (token.kind) {

            // Appears at beginning of statement
            //  so we can sync here
            .@"{",
            .@"let",
            .@"if",
            .@"while",
            .@"return",
            .@"print",
            .@"break",
            .@"continue" => return .statement,
            
            // End of block
            .@"}" => return .empty,

            // End of statement
            .@";" => {
                _ = try self.lexer.take(); // ;
                return .statement;
            },

            // Skip
            else => {
                _ = try self.lexer.take();
            },
        }

    } else return .empty;
}

fn matchOrNull(
    self: *Self,
    comptime action: Action,
    kind: Token.Kind
) !?Token {
    
    if (try self.lexer.peek()) |peek| {
        if (peek.kind == kind) {
            if (action == .take) {
                _ = try self.lexer.take();
            }
            return peek;
        }
    }

    return null;
}

fn matchOneOfOrNull(
    self: *Self,
    comptime action: Action,
    comptime matches: []const Token.Kind 
) !?Token {
    
    if (try self.lexer.peek()) |peek| {

        inline for (matches) |kind| {
            if (peek.kind == kind) {
                if (action == .take) {
                    _ = try self.lexer.take();
                }
                return peek;
            }
        }
    }

    return null;
}

fn expect(
    self: *Self,
    comptime action: Action,
    expected: Token.Kind
) !Token {

    const token = switch (action) {
        .take => try self.lexer.take(),
        .peek => try self.lexer.peek(),
    };
    
    if (token) |found| {
        if (found.kind == expected) {
            return found;
        } else {
            try self.pushError(.{
                .stage = .parsing,
                .where = found.where,
                .kind  = .{ 
                    .unexpected_token = .{
                        .expected = expected,
                        .found    = found.kind,
                    },
                },
            });
            unreachable;
        }
    } else {

        try self.pushError(.{
            .stage = .parsing,
            .kind  = .unexpected_eoi,
        });
        unreachable;
    }
}

fn expectOneOf(
    self: *Self,
    comptime action: Action,
    comptime expected_list: []const Token.Kind
) !Token {

    const token = switch (action) {
        .take => try self.lexer.take(),
        .peek => try self.lexer.peek(),
    };

    if (token) |found| {

        inline for (expected_list) |expected| {
            if (found.kind == expected) {
                return found;
            }
        } else {
            try self.pushError(.{
                .stage = .parsing,
                .where = found.where,
                .kind  = .{ 
                    .unexpected_token_oneof = .{
                        .expected = expected_list,
                        .found    = found.kind,
                    },
                },
            });
            unreachable;
        }
    } else {

        try self.pushError(.{
            .stage = .parsing,
            .kind  = .unexpected_eoi,
        });
        unreachable;
    }
}

fn topLevelList(self: *Self) anyerror!usize {
    
    const decl = try self.topLevel();
    const next = if (try self.lexer.peek()) |_| try self.topLevelList() else null;
    
    return try self.ast.push(.{
        .toplevel_list = .{
            .decl = decl,
            .next = next,
        },
    });
}

fn topLevel(self: *Self) anyerror!usize {

    const begin = try self.expectOneOf(.peek, &[_] Token.Kind { .@"fn", });

    return switch (begin.kind) {
        .@"fn" => try self.function(),
        else => unreachable,
    };
}

fn function(self: *Self) anyerror!usize {

    _ = try self.lexer.take(); // fn 
    const name = try self.expect(.take, .identifier);
    _ = try self.expect(.take, .@"(");

    // Parameters may be empty
    var params: ?usize = undefined;
    if (try self.lexer.peek()) |peek| {
        if (peek.kind == .@")") {
            _ = try self.lexer.take(); // )
            params = null;
        } else {
            params = try self.parameterList();
        }
    } else {
        try self.pushError(.{
            .stage = .parsing,
            .kind  = .unexpected_eoi,
        });
    }

    _ = try self.expect(.take, .@":");
    const return_token = try self.expectOneOf(
        .take,
        &[_] Token.Kind { .@"int", .@"bool", }
    );
    const return_type: Type = switch (return_token.kind) {
        .@"int"  => .integer,
        .@"bool" => .boolean,
        else => unreachable,
    };

    _ = try self.expect(.take, .@"=");
    const body = try self.block();

    return self.ast.push(.{
        .function = .{
            .name        = name,
            .params      = params,
            .return_type = return_type,
            .body        = body,
        },
    });
}

fn parameterList(self: *Self) anyerror!usize {

    const name = try self.expect(.take, .identifier);
    _ = try self.expect(.take, .@":");
    const type_token = try self.expectOneOf(
        .take,
        &[_] Token.Kind { .@"int", .@"bool", }
    );
    const type_: Type = switch (type_token.kind) {
        .@"int" => .integer,
        .@"bool" => .boolean,
        else => unreachable, // invalid type identifier
    };
    const delimiter = try self.expectOneOf(.take, &[_]Token.Kind { .@",", .@")", });

    const next = switch (delimiter.kind) {
        .@"," => try self.parameterList(),
        .@")" => null,
        else => unreachable,
    };

    return self.ast.push(.{
        .parameter_list = .{
            .name = name,
            .type_ = type_,
            .next = next,
        },
    });
}

fn block(self: *Self) anyerror!usize {

    _ = try self.expect(.take, .@"{");
    const content = if (try self.matchOrNull(.peek, .@"}")) |_|
        try self.ast.push(.empty) else try self.statementList();
    _ = try self.expect(.take, .@"}");

    return self.ast.push(.{
        .block = .{
            .content = content,
        },
    });
}

fn statementList(self: *Self) anyerror!usize {

    const begin = try self.expectOneOf(.peek, &[_] Token.Kind {
        .@"{",
        .@"}",
        .@"let",
        .@"if",
        .@"while",
        .@"return",
        .@"break",
        .@"continue",
        .@"print",
        .identifier,
    });

    const stmnt = switch(begin.kind) {
        .@"{"        => self.block(),
        .@"let"      => self.declaration(),
        .@"if"       => self.ifStatement(),
        .@"while"    => self.whileStatement(),
        .@"return"   => self.returnStatement(),
        .@"break"    => self.breakStatement(),
        .@"continue" => self.continueStatement(),
        .@"print"    => self.printStatement(),
        .identifier  => self.assignment(),
        .@"}"        => error.ParseError, // sync
        else         => unreachable,
    } catch |err| recover: {
        if (err == error.ParseError) {
            break :recover switch (try self.sync()) {
                .empty     => try self.ast.push(.empty),
                .statement => try self.statementList(),
            };
        } else return err; // memory error
    };

    var next: ?usize = undefined;
    if (try self.lexer.peek()) |peek| {
        if (peek.kind == .@"}") {
            next = null;
        } else {
            next = try self.statementList();
        }
    } else {
        next = null;
    }

    return self.ast.push(.{
        .statement_list = .{
            .statement = stmnt,
            .next = next,
        },
    });
}

fn breakStatement(self: *Self) anyerror!usize {
    const token = try self.expect(.take, .@"break");
    _ = try self.expect(.take, .@";");
    return self.ast.push(.{
        .break_statement = token.where,
    });
}

fn continueStatement(self: *Self) anyerror!usize {
    const token = try self.expect(.take, .@"continue");
    _ = try self.expect(.take, .@";");
    return self.ast.push(.{
        .continue_statement = token.where,
    });
}

fn declaration(self: *Self) anyerror!usize {

    _ = try self.expect(.take, .@"let");
    const name = try self.expect(.take, .identifier);
    _ = try self.expect(.take, .@":");
    const type_token = try self.expectOneOf(
        .take,
        &[_] Token.Kind { .@"int", .@"bool", }
    );
    const type_: Type = switch (type_token.kind) {
        .@"int" => .integer,
        .@"bool" => .boolean,
        else => unreachable, // invalid type identifier
    };
    _ = try self.expect(.take, .@"=");
    const expr = try self.expression();
    _ = try self.expect(.take, .@";");

    return self.ast.push(.{
        .declaration = .{
            .name  = name,
            .type_ = type_,
            .expr  = expr,
        },
    });
}

fn assignment(self: *Self) anyerror!usize {

    const name = try self.expect(.take, .identifier);
    const operator = try self.expectOneOf(.take,
        &[_] Token.Kind {
            .@"=",
            .@"+=",
            .@"-=",
            .@"*=",
            .@"/=",
            .@"%=",
        }
    );
    const expr = try self.expression();
    _ = try self.expect(.take, .@";");

    return self.ast.push(.{
        .assignment = .{
            .name = name,
            .operator = operator,
            .expr = expr,
        },
    });
}

fn ifStatement(self: *Self) anyerror!usize {

    const keyword = try self.expect(.take, .@"if");
    const condition = try self.expression();
    const if_block = try self.block();
    const else_block = if (try self.matchOrNull(.take, .@"else")) |_|
        try self.block() else null;

    return self.ast.push(.{
        .if_statement = .{
            .keyword = keyword,
            .condition = condition,
            .block = if_block,
            .else_block = else_block,
        },
    });
}

fn whileStatement(self: *Self) anyerror!usize {

    const keyword = try self.expect(.take, .@"while");
    const condition = try self.expression();
    const while_block = try self.block();

    return self.ast.push(.{
        .while_statement = .{
            .keyword = keyword,
            .condition = condition,
            .block = while_block,
        },
    });
}

fn expression(self: *Self) anyerror!usize {
    
    var left = try self.equality();

    while (try self.matchOneOfOrNull(.peek,
        &[_] Token.Kind { .@"and", .@"or", })) |operator|
    {
        _ = try self.lexer.take(); // operator
        const right = try self.equality();
        left = try self.ast.push(.{
            .binary = .{
                .left     = left,
                .right    = right,
                .operator = operator,
            },
        });
    }

    return left;
}

fn equality(self: *Self) anyerror!usize {

    var left = try self.comparison();

    while (try self.matchOneOfOrNull(.peek,
        &[_] Token.Kind { .@"==", .@"!=", })) |operator|
    {
        _ = try self.lexer.take(); // operator
        const right = try self.comparison();
        left = try self.ast.push(.{
            .binary = .{
                .left     = left,
                .right    = right,
                .operator = operator,
            },
        });
    }

    return left;
}

fn comparison(self: *Self) anyerror!usize {

    var left = try self.sum();

    while (try self.matchOneOfOrNull(.peek,
        &[_] Token.Kind { .@"<", .@"<=", .@">", .@">=", })) |operator|
    {
        _ = try self.lexer.take(); // operator
        const right = try self.sum();
        left = try self.ast.push(.{
            .binary = .{
                .left     = left,
                .right    = right,
                .operator = operator,
            },
        });
    }

    return left;
}

fn sum(self: *Self) anyerror!usize {

    var left = try self.product();

    while (try self.matchOneOfOrNull(.peek,
        &[_] Token.Kind { .@"+", .@"-", })) |operator|
    {
        _ = try self.lexer.take(); // operator
        const right = try self.product();
        left = try self.ast.push(.{
            .binary = .{
                .left     = left,
                .right    = right,
                .operator = operator,
            },
        });
    }

    return left;
}

fn product(self: *Self) anyerror!usize {

    var left = try self.factor();

    while (try self.matchOneOfOrNull(.peek,
            &[_] Token.Kind { .@"*", .@"/", .@"%", })) |operator|
    {
        _ = try self.lexer.take(); // operator
        const right = try self.factor();
        left = try self.ast.push(.{
            .binary = .{
                .left     = left,
                .right    = right,
                .operator = operator,
            },
        });
    }

    return left;
}

fn factor(self: *Self) anyerror!usize {

    const begin = try self.expectOneOf(.peek,
        &[_] Token.Kind {
            .@"-",
            .@"!",
            .@"(",
            .@"true",
            .@"false",
            .identifier,
            .literal,
        }
    );

    return switch (begin.kind) {

        .identifier => try self.reference(),

        .literal => literal: {
            _ = try self.lexer.take(); // literal
            break :literal try self.ast.push(.{
                .constant = .{
                    .type_ = .integer,
                    .token = begin,
                },
            });
        },

        .@"true", .@"false" => boolean: {
            _ = try self.lexer.take(); // true / false
            break :boolean try self.ast.push(.{
                .constant = .{
                    .type_ = .boolean,
                    .token = begin,
                }
            });
        },

        .@"-", .@"!" => try self.unary(),

        .@"(" => surrounded: {
            _ = try self.lexer.take(); // (
            const expr = try self.expression();
            _ = try self.expect(.take, .@")");
            break :surrounded expr;
        },

        else => unreachable,
    };
}

fn reference(self: *Self) anyerror!usize {

    const name = try self.expect(.take, .identifier);
    
    if (try self.matchOrNull(.take, .@"(")) |_| {

        const args = if (try self.matchOrNull(.take, .@")")) |_|
            null else try self.argumentList();

        return self.ast.push(.{
            .call = .{
                .name = name,
                .args = args,
            },
        });
    } else {

        return self.ast.push(.{
            .variable = .{
                .name = name,
            },
        });
    }
}

fn argumentList(self: *Self) anyerror!usize {

    const expr = try self.expression();
    const delimiter = try self.expectOneOf(.take, &[_] Token.Kind { .@",", .@")", });

    const next = switch (delimiter.kind) {
        .@"," => try self.argumentList(),
        .@")" => null,
        else => unreachable,
    };

    return self.ast.push(.{
        .argument_list = .{
            .delimiter = delimiter,
            .expr = expr,
            .next = next,
        },
    });
}

fn returnStatement(self: *Self) anyerror!usize {

    const keyword = try self.expect(.take, .@"return");
    const expr = try self.expression();
    _ = try self.expect(.take, .@";");

    return self.ast.push(.{
        .return_statement = .{
            .keyword = keyword,
            .expr = expr,
        },
    });
}

fn printStatement(self: *Self) anyerror!usize {

    _ = try self.expect(.take, .@"print");
    const expr = try self.expression();
    _ = try self.expect(.take, .@";");

    return self.ast.push(.{
        .print_statement = .{
            .expr = expr,
        },
    });
}

fn unary(self: *Self) anyerror!usize {
    
    const operator = try self.expectOneOf(.take, &[_] Token.Kind { .@"-", .@"!", });
    const operand = try self.factor();
    
    return self.ast.push(.{
        .unary = .{
            .operator = operator,
            .operand = operand,
        },
    });
}
