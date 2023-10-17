
const std = @import("std");

const Lexer       = @import("Lexer.zig");
const Ast         = @import("Ast.zig");
const Parser      = @import("Parser.zig");
const TypeChecker = @import("TypeChecker.zig");

pub fn main() !u8 {

    const source =
        \\ fn add(a, b) = {
        \\     let c = a + b;
        \\     c += 1;
        \\     if (b == a) == (c < c) {
        \\         c = 0;
        \\     } else {
        \\         c -= 2;
        \\     }
        \\     return c;
        \\ }
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var stdout = std.io.getStdOut().writer();

    var lexer = Lexer.init(source, allocator); 
    defer lexer.deinit();

    try lexer.dump(stdout);
    lexer.reset();

    var ast = Ast.init(allocator);
    defer ast.deinit();

    // Parse
    var parser = Parser.init(&lexer, &ast, allocator);
    defer parser.deinit();

    parser.parse() catch {
        
        for (parser.errors.items) |*err| {
            try err.print(source, stdout);
        }

        return 1;
    };
    try ast.dump(stdout);

    var type_checker = TypeChecker.init(&ast, allocator);
    defer type_checker.deinit();
    type_checker.check() catch {

        for (type_checker.errors.items) |err| {
            try err.print(source, stdout);
        }

        return 1;
    };

    return 0;
}
