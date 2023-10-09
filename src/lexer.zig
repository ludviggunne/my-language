
const std = @import("std");

const TokenKind = @import("token.zig").TokenKind;
const Token     = @import("token.zig").Token;

const keywords = std.ComptimeStringMap(TokenKind, .{
    .{ "if",    .@"if", },
    .{ "else",  .@"else", },
    .{ "while", .@"while", },
    .{ "let",   .@"let", },
});

pub const TokenStream = struct {

    const Self = @This();

    tokens: std.ArrayList(Token),
    markers: std.ArrayList(usize),
    index: usize,

    pub fn init(allocator: std.mem.Allocator) Self {

        return .{
            .tokens = std.ArrayList(Token).init(allocator),
            .markers = std.ArrayList(usize).init(allocator),
            .index = 0,
        };
    }

    pub fn pushMarker(self: *Self) !void {
        try self.markers.append(self.index);
    }

    pub fn popMarker(self: *Self) void {
        if (self.markers.pop()) |index| {
            self.index = index;
        }
    }

    pub fn atEnd(self: *Self) bool {
        return self.index == self.tokens.items.len;
    }

    pub fn current(self: *Self) ?Token {

        if (self.index > 0 and self.index <= self.tokens.items.len) {
            return self.tokens.items[self.index - 1];
        } else return null;
    }

    pub fn next(self: *Self) ?Token {

        if (!self.atEnd()) {
            defer self.index += 1;
            return self.tokens.items[self.index];
        } else return null;
    }

    pub fn previous(self: *Self) ?Token {

        if (self.index > 0) {
            return self.tokens.items[self.index - 1];
        } else return null;
    }

    pub fn peek(self: *Self) ?Token {

        if (self.index < self.tokens.items.len) {
            return self.tokens.items[self.index];
        } else return null;
    }

    pub fn back(self: *Self) !void {
        
        if (self.index > 0) {
            self.index -= 1;
        } else return error.AtBeginning;
    }
};

pub const Lexer = struct {

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

    pub fn collect(self: *Self, allocator: std.mem.Allocator) !TokenStream {

        var stream = TokenStream.init(allocator);

        while (self.next()) |token| {

            try stream.tokens.append(token);
        }

        return stream;
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
                        .kind = .literal,
                        .loc  = self.source[begin..self.index],
                    };
                }
            }
        }

        // Single operator
        var kind: ?TokenKind = switch (current) {
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
                .loc = self.source[begin..self.index],
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
                .loc  = self.source[begin..self.index],
            };
        }

        // Unrecognized character
        return .{
            .kind = .err,
            .loc = self.source[begin..self.index],
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
};
