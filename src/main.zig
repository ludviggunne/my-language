const std = @import("std");
const lexer = @import("lexer.zig");

pub fn main() void {

    var stdout = std.io.getStdOut().writer();

    var source =
        \\ int x = 10;
        \\ int y = x + 1;
        \\ int z = x - y;
        ;

    var lex = lexer.Lexer.init(source[0..]);
    while (lex.next()) |tok| {
        stdout.print("{s}: \"{s}\"\n", .{ @tagName(tok.kind), tok.loc, }) 
            catch unreachable;
    }
}
