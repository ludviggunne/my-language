
pub const Kind = enum {

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
    @"print",   // print

    err,
};

kind:  Kind,
begin: usize,
end:   usize,