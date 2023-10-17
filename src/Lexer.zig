
const std = @import("std");
const Self = @This();

const Error = @import("Error.zig");
const Token = @import("Token.zig");

const keywords = std.ComptimeStringMap(
    Token.Kind,
    .{
        .{ "if",       .@"if",       },
        .{ "else",     .@"else",     },
        .{ "while",    .@"while",    },
        .{ "let",      .@"let",      },
        .{ "fn",       .@"fn",       },
        .{ "return",   .@"return",   },
        .{ "break",    .@"break",    },
        .{ "print",    .@"print",    },
        .{ "continue", .@"continue", },
    }
);

source: []const u8,
index:  usize,
peeked: ?Token,
errors: std.ArrayList(Error),

pub fn init(source: []const u8, allocator: std.mem.Allocator) Self {
    return .{
        .source = source,
        .index  = 0,
        .peeked = null,
        .errors = std.ArrayList(Error).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.errors.deinit();
}

pub fn dump(self: *Self, writer: anytype) !void {
    
    try writer.print("---------- Lexer dump ----------\n", .{});
    while (try self.take()) |token| {
        try writer.print(
            "{0s: <16}{1s}\n",
            .{
                @tagName(token.kind),
                token.where,
            } 
        );
    }
}

pub fn reset(self: *Self) void {

    self.index = 0;
    self.peeked = null;
    self.errors.clearRetainingCapacity();
}

pub fn take(self: *Self) !?Token {

    var curr: u8 = undefined;
    var begin: usize = undefined;

    if (self.peeked) |_| {
        defer self.peeked = null;
        return self.peeked;
    }

    trim: while (self.takeChar()) |char| {
        switch (char) {

            // Empty
            ' ', '\n', '\t' => {},

            // Comments
            '#' => {
                while (self.takeChar()) |comment| {
                    if (comment == '\n') {
                        continue :trim;
                    }
                } else return null; // eoi
            },

            // Token
            else => {
                curr = char;
                begin = self.index - 1;
                break :trim;
            },
        }
    } else return null; // eoi

    // Single operator
    const single: ?Token.Kind = switch (curr) {
        ';' => .@";",
        ',' => .@",",
        '{' => .@"{",
        '}' => .@"}",
        '(' => .@"(",
        ')' => .@")",
        else => null,
    };
    
    if (single) |kind| {
        return .{
            .kind = kind,
            .where= self.source[begin..self.index],
        };
    }

    // Possibly multi-character operator
    const eql = if (self.peekChar()) |after| blk: {
        if (after == '=') {
            _ = self.takeChar(); // =
            break :blk true;
        }
        break :blk false;
    } else false;

    const multi: ?Token.Kind = switch (curr) {
        '+'  => if (eql) .@"+=" else .@"+",
        '-'  => if (eql) .@"-=" else .@"-",
        '*'  => if (eql) .@"*=" else .@"*",
        '/'  => if (eql) .@"/=" else .@"/",
        '%'  => if (eql) .@"%=" else .@"%",
        '!'  => if (eql) .@"!=" else .@"!",
        '='  => if (eql) .@"==" else .@"=",
        '<'  => if (eql) .@"<=" else .@"<",
        '>'  => if (eql) .@">=" else .@">",
        else => null,
    };

    if (multi) |kind| {
        return .{
            .kind  = kind,
            .where = self.source[begin..self.index],
        };
    }

    // Identifier
    if (alpha(curr)) {

        while (self.peekChar()) |c| {
            if (alphaNumeric(c)) {
                _ = self.takeChar();
            } else break;
        }

        const name = self.source[begin..self.index];
        const kind = keywords.get(name) orelse .identifier;
        return .{
            .kind  = kind,
            .where = name,
        };
    }

    // Numeric constant
    if (numeric(curr)) {
        
        while (self.peekChar()) |c| {
            if (numeric(c)) {
                _ = self.takeChar();
            } else break;
        }

        return .{
            .kind  = .literal,
            .where = self.source[begin..self.index],
        };
    }

    // Error
    const location = self.source[begin..self.index];

    try self.errors.append(.{
        .stage = .lexing,
        .where = location,
        .kind  = .{ .unexpected_character = self.source[begin..self.index], },
    });

    return .{
        .kind  = .err,
        .where = location,
    };
}

pub fn peek(self: *Self) !?Token {
    if (self.peeked == null) {
        self.peeked = try self.take();
    }

    return self.peeked;
}

fn takeChar(self: *Self) ?u8 {
    
    if (self.index < self.source.len) {
        defer self.index += 1;
        return self.source[self.index];
    } else return null;
}

fn peekChar(self: *Self) ?u8 {
    
    if (self.index < self.source.len) {
        return self.source[self.index];
    } else return null;
}

fn alpha(char: u8) bool {
    return
        ('a' <= char and char <= 'z') or
        ('A' <= char and char <= 'Z') or
        char == '_';
}

fn numeric(char: u8) bool {
    return '0' <= char and char <= '9';
}

fn alphaNumeric(char: u8) bool {
    return alpha(char) or numeric(char);
}
