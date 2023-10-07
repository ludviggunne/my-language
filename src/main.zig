
const std = @import("std");
const lexer = @import("lexer.zig");

pub fn main() !void {

    const stdout = std.io.getStdOut().writer();

    // Read file
    var bufalloc = std.heap.GeneralPurposeAllocator(.{}) {};
    const cwd = std.fs.cwd();
    const file = try cwd.openFile("./source.l", .{});
    const buffer = try file.readToEndAlloc(bufalloc.allocator(), 1024);

    // Lex file
    var lex = lexer.Lexer.init(buffer);

    while (lex.next()) |tok| {
        try stdout.print("{s: <16} {s}\n", .{ @tagName(tok.kind), tok.loc, });
    }
}
