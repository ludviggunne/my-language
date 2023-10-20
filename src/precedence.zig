
const std = @import("std");
const Token = @import("Token.zig");

const categories = & [_] [] const Token.Kind {
    &[_] Token.Kind { .@"<", .@"<=", .@"==", .@">=", .@">", .@"!=", },
    &[_] Token.Kind { .@"+", .@"-", },
    &[_] Token.Kind { .@"*", .@"/", .@"%", },
};

const data: struct { 
    values: std.EnumArray(Token.Kind, usize),
    count: usize,
} = blk: {

    var v = std.EnumArray(Token.Kind, usize).initUndefined(); 
    var i: usize = 0;

    for (categories) |c| {
        for (c) |t| {
            v.set(t, i);
        }
        i += 1;
    }

    break :blk .{
        .values = v,
        .count = i,
    };
};

pub const values = data.values;
pub const count = data.count;

pub fn of(token: Token) usize {
    return values.get(token.kind); 
}
