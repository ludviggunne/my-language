
const std = @import("std");

const Token = @import("Token.zig");

const keywords = std.ComptimeStringMap(Token.Kind, .{
    .{ "if",    .@"if", },
    .{ "else",  .@"else", },
    .{ "while", .@"while", },
    .{ "let",   .@"let", },
    .{ "print", .@"print", },
});

const Self = @This();

source: []const u8,
index:  usize,
peeked: ?Token,

pub fn init(source: []const u8) Self {

    return .{
        .source = source,
        .index  = 0,
        .peeked = null,
    };
}

pub fn next(self: *Self) ?Token {

    if (self.peeked) |_| {
        defer self.peeked = null;
        return self.peeked;
    }

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
                    .begin = begin,
                    .end = self.index,
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
                    .kind = .literal,
                    .begin = begin,
                    .end = self.index,
                };
            }
        }
    }

    // Single operator
    var kind: ?Token.Kind = switch (current) {
        ';' => .@";",
        ':' => .@":",
        '(' => .@"(",
        ')' => .@")",
        '{' => .@"{",
        '}' => .@"}",
        else => null,
    };

    if (kind) |k| {
        return .{
            .kind = k,
            .begin = begin,
            .end = self.index,
        };
    }

    // Optionally multi-character operators
    var eq = if (self.peek_c()) |ch| ch == '=' else false;
    if (eq) { _ = self.take(); }

    kind = switch (current) {
        '+' => if (eq) .@"+=" else .@"+",
        '-' => if (eq) .@"-=" else .@"-",
        '*' => if (eq) .@"*=" else .@"*",
        '/' => if (eq) .@"/=" else .@"/",
        '=' => if (eq) .@"==" else .@"=",
        '>' => if (eq) .@">=" else .@">",
        '<' => if (eq) .@"<=" else .@"<",
        '!' => if (eq) .@"!=" else .@"!",
        else => null,
    };

    if (kind) |k| {
        return .{
            .kind = k,
            .begin = begin,
            .end = self.index,
        };
    }

    // Unrecognized character
    return .{
        .kind = .err,
        .begin = begin,
        .end = self.index,
    };
}

pub fn peek(self: *Self) ?Token {

    if (self.peeked == null) {
        self.peeked = self.next();
    }

    return self.peeked;
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

fn peek_c(self: *Self) ?u8 {

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
