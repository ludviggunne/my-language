
pub const TokenKind = enum {

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
    colon,       // :
    lpar,        // (
    rpar,        // )
    lbrc,        // {
    rbrc,        // }

    if_kw,       // if
    while_kw,    // while
    else_kw,     // else

    err,
};
