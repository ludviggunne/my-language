
pub const TokenKind = enum {

    identifier, // int, var
    literal,    // 1232

    @"+",       // +
    @"-",       // -
    @"*",       // *
    @"/",       // /
    @"=",       // =
    @">",       // >
    @"<",       // <
    @"!",       // !

    @"+=",      // +=
    @"-=",      // -=
    @"*=",      // *=
    @"/=",      // /=
    @"==",      // ==
    @">=",      // >=
    @"<=",      // <=
    @"!=",      // !=

    @";",       // ;
    @":",       // :
    @"(",       // (
    @")",       // )
    @"{",       // {
    @"}",       // }

    @"if",      // if
    @"while",   // while
    @"else",    // else
    @"let",     // let

    err,
};

pub const Token = struct {

    kind: TokenKind,
    loc:  []const u8,
};
