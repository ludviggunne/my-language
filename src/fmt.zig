
const std = @import("std");

const Parser    = @import("Parser.zig");
const Lexer     = @import("Lexer.zig");
const Ast       = @import("Ast.zig");
const Formatter = @import("Formatter.zig");

pub fn main() !u8 {

    const stdout = std.io.getStdOut().writer();
    const stdin  = std.io.getStdIn();

    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const source = try stdin.readToEndAlloc(allocator, 2048);
    defer allocator.free(source);

    var lexer = Lexer.init(source, allocator); 
    defer lexer.deinit();

    var ast = Ast.init(allocator);
    defer ast.deinit();

    var parser = Parser.init(&lexer, &ast, allocator);
    defer parser.deinit();

    parser.parse() catch return 1;

    var fmt = Formatter.init(&ast);
    fmt.format(stdout) catch return 1;

    return 0;
}
