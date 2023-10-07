
const std = @import("std");

const keywords = std.ComptimeStringMap(TokenKind, .{
    .{ "if",    .if_kw, },
    .{ "else",  .else_kw, },
    .{ "while", .while_kw, },
});

pub const TokenKind = union(enum) {

    identifier,  // int, var
    int_literal, // 1232

    plus,        // +
    minus,       // -
    mul,         // *
    div,         // /
    assign,      // =
    greater,     // >
    less,        // <
    not,         // !

    plus_eq,     // +=
    minus_eq,    // -=
    mul_eq,      // *=
    div_eq,      // /=
    equal,       // ==
    geq,         // >=
    leq,         // <=
    neq,         // !=

    semi,        // ;
    lpar,        // (
    rpar,        // )
    lbrc,        // {
    rbrc,        // }

    if_kw,       // if
    while_kw,    // while
    else_kw,     // else

    err: enum {
        invalid_character,
    },
};

pub const Token = struct {

    kind: TokenKind,
    loc:  []const u8,
};

pub const Lexer = struct {

    const Self = @This();

    source: []const u8,
    index:  usize,
    
    pub fn init(source: []const u8) Self {

        return .{
            .source = source,
            .index  = 0,
        };
    }

    pub fn next(self: *Self) ?Token {

        // Skip whitespace
        var current: u8 = undefined;
        var begin: usize = undefined;

        while (self.take()) |ch| {
            if (!whitespace(ch)) {
                current = ch;
                begin = self.index - 1;
                break;
            }
        } else return null;

        // Identifier
        if (alpha(current)) {

            while (self.take()) |ch| {

                if (!alpha_numeric(ch)) {

                    self.back();
                    const loc = self.source[begin..self.index];

                    const kind = if (keywords.get(loc)) |kind|
                        kind else .identifier;

                    return .{
                        .kind = kind,
                        .loc = self.source[begin..self.index],
                    };
                }
            }
        }

        // Number literal
        if (numeric(current)) {

            while (self.take()) |ch| {

                if (!numeric(ch)) {
                    self.back();
                    return .{
                        .kind = .int_literal,
                        .loc  = self.source[begin..self.index],
                    };
                }
            }
        }

        // Single operator
        var kind: ?TokenKind = switch (current) {
            ';' => .semi,
            '(' => .lpar,
            ')' => .rpar,
            '{' => .lbrc,
            '}' => .rbrc,
            else => null,
        };

        if (kind) |k| {
            return .{
                .kind = k,
                .loc = self.source[begin..self.index],
            };
        }

        // Optionally multi-character operators
        var eq = if (self.peek()) |ch| ch == '=' else false;
        if (eq) { _ = self.take(); }

        kind = switch (current) {
            '+' => if (eq) .plus_eq  else .plus,
            '-' => if (eq) .minus_eq else .minus,
            '*' => if (eq) .mul_eq   else .mul,
            '/' => if (eq) .div_eq   else .div,
            '=' => if (eq) .equal    else .assign,
            '>' => if (eq) .geq      else .greater,
            '<' => if (eq) .leq      else .less,
            '!' => if (eq) .neq      else .not,
            else => null,
        };

        if (kind) |k| {
            return .{
                .kind = k,
                .loc  = self.source[begin..self.index],
            };
        }

        // Unrecognized character
        return .{
            .kind = .{ .err = .invalid_character, },
            .loc = self.source[begin..self.index],
        };
    }

    fn take(self: *Self) ?u8 {

        if (self.index < self.source.len) {
            defer self.index += 1;
            return self.source[self.index];
        } else {
            return null;
        }
    }

    fn back(self: *Self) void {
        self.index -= 1;
    }

    fn peek(self: *Self) ?u8 {

        return if (self.index < self.source.len)
            self.source[self.index]
        else
            null;
    }

    fn whitespace(ch: u8) bool {

        return
            ch == ' '  or
            ch == '\t' or
            ch == '\n';
    }

    fn alpha(ch: u8) bool {

        return (ch >= 'a' and ch <= 'z')
            or (ch >= 'A' and ch <= 'Z')
            or ch == '_';
    }

    fn numeric(ch: u8) bool {

        return ch >= '0' and ch <= '9';
    }

    fn alpha_numeric(ch: u8) bool {

        return alpha(ch) or numeric(ch);
    }
};
