
const std = @import("std");
const lexer = @import("lexer.zig");

comptime {
    _ = @import("parser/grammar.zig");
    _ = @import("parser/grammar.zig").grammar;
}

pub fn main() !void {

    const stdout = std.io.getStdOut().writer();

    // Read file
    var bufalloc = std.heap.GeneralPurposeAllocator(.{}) {};
    const cwd = std.fs.cwd();
    const file = try cwd.openFile("./test.l", .{});
    const buffer = try file.readToEndAlloc(bufalloc.allocator(), 1024);

    // Lex file
    var lex = lexer.Lexer.init(buffer);

    while (lex.next()) |tok| {
        try stdout.print("{s: <16} {s}\n", .{ @tagName(tok.kind), tok.loc, });
    }

    // Print FIRST sets
    for (std.enums.values(@import("parser/nonterm.zig").NonTerm)) |nonterm| {

        const set = @import("parser/first.zig").first.get(nonterm);

        try stdout.print("{s}:\n", .{ @tagName(nonterm), });

        var iter = set.iterator();
        while (iter.next()) |term| {
            try stdout.print("    {s}\n", .{ @tagName(term), });
        }
    }
}
