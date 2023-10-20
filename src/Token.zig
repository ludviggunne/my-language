
const Self = @This();
const Error = @import("Error.zig");

pub const Kind = enum {
    @"+",
    @"-",
    @"*",
    @"/",
    @"%",
    @"+=",
    @"-=",
    @"*=",
    @"/=",
    @"%=",
    @"<",
    @">",
    @"=",
    @"!",
    @"<=",
    @">=",
    @"==",
    @"!=",
    @"(",
    @")",
    @"{",
    @"}",
    @":",
    @";",
    @",",

    @"if",
    @"else",
    @"while",
    @"break",
    @"continue",
    @"let",
    @"fn",
    @"return",
    @"print",
    @"and",
    @"or",

    identifier,
    literal,

    err,
};

kind: Kind,
where: []const u8,

pub fn printReference(self: *Self, source: []const u8, writer: anytype) !void {

    try Error.printReference(self.where, source, writer);
}
