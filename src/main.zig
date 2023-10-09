
const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

pub fn main() !void {

    const stdout = std.io.getStdOut().writer();

    // Read file
    var bufalloc = std.heap.GeneralPurposeAllocator(.{}) {};
    const cwd = std.fs.cwd();
    const file = try cwd.openFile("./test.l", .{});
    const buffer = try file.readToEndAlloc(bufalloc.allocator(), 1024);

    // Lex file
    var lex = Lexer.init(buffer);
    var stream = try lex.collect(bufalloc.allocator());

    for (stream.tokens.items) |tok| {
        try stdout.print("{s: <16}{s}\n", .{ @tagName(tok.kind), tok.loc, });
    }

    var parser = Parser.init(bufalloc.allocator(), &stream);
    const ast = parser.parse() catch {

        for (parser.errors.items) |err| {

            switch (err.kind) {
                .expected_token => |e| try stdout.print(
                    "Expected token {s}, found {s}\n",
                    .{ @tagName(e),
                    err.location orelse "null", }
                ),
                .expected_token_range => |r| {
                    try stdout.print("Expected one of ", .{});
                    for (r) |tok| {
                        try stdout.print("{s}, ", .{ @tagName(tok) });
                    }
                    try stdout.print("found {s}\n", .{ err.location orelse "null", });
                },
                .unexpected_eoi => try stdout.print("Unexpected end of input\n", .{}),
            }
        }

        return error.NOOO;
    };

    @import("ast.zig").print(parser.nodes.items, ast);
}
