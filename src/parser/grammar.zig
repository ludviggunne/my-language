
const std = @import("std");

const TokenKind = @import("../token.zig").TokenKind;
const NonTerm   = @import("nonterm.zig").NonTerm;

const Symbol = union(enum) {
    term:    TokenKind,
    nonterm: NonTerm,
};

const Rule = struct {
    left:  NonTerm,
    right: []const Symbol,
};

pub const grammar = [_]Rule {
    
    .{
        // <expression> ::= <expression> "+" <term>
        .left = .expression, 
        .right = &[_]Symbol {
            .{ .nonterm = .expression, },
            .{ .term    = .plus, },
            .{ .nonterm = .term, },
        },
    },

    .{
        // <expression> ::= <expression> "-" <term>
        .left = .expression, 
        .right = &[_]Symbol {
            .{ .nonterm = .expression, },
            .{ .term    = .minus, },
            .{ .nonterm = .term, },
        },
    },

    .{
        // <expression> ::= <term>
        .left = .expression,
        .right = &[_]Symbol {
            .{ .nonterm = .term, },
        },
    },

    .{
        // <term> ::= <term> "*" <factor>
        .left = .term,
        .right = &[_]Symbol {
            .{ .nonterm = .term, },
            .{ .term    = .mul, },
            .{ .nonterm = .factor, },
        },
    },

    .{
        // <term> ::= <term> "/" <factor>
        .left = .term,
        .right = &[_]Symbol {
            .{ .nonterm = .term, },
            .{ .term    = .div, },
            .{ .nonterm = .factor, },
        },
    },

    .{
        // <term> ::= <factor>
        .left = .term,
        .right = &[_]Symbol {
            .{ .nonterm = .factor, },
        },
    },

    .{
        // <factor> ::= "-" <factor>
        .left = .factor,
        .right = &[_]Symbol {
            .{ .term    = .minus, },
            .{ .nonterm = .factor, },
        },
    },

    .{
        // <factor> ::= "(" <expression> ")"
        .left = .factor,
        .right = &[_]Symbol {
            .{ .term    = .lpar, },
            .{ .nonterm = .expression, },
            .{ .term    = .rpar, },
        },
    },

    .{
        // <factor> ::= "identifier"
        .left = .factor,
        .right = &[_]Symbol {
            .{ .term = .identifier, },
        },
    },

    .{
        // <factor> ::= "int_literal"
        .left = .factor,
        .right = &[_]Symbol {
            .{ .term = .int_literal, },
        },
    },
};
