
const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const SourceRef = @import("SourceRef.zig");

pub fn main() !void {

    // Read file
    var bufalloc = std.heap.GeneralPurposeAllocator(.{}) {};
    const cwd = std.fs.cwd();
    const file = try cwd.openFile("./test.l", .{});
    const buffer = try file.readToEndAlloc(bufalloc.allocator(), 1024);

    // Lex file
    var lex = Lexer.init(buffer);
    var stream = try lex.collect(bufalloc.allocator());

    var line: usize = 1;
    std.debug.print("1:{s: <4}", .{ "", });
    for (buffer) |c| {
        std.debug.print("{c}", .{ c, });
        if (c == '\n') {
            line += 1; 
            std.debug.print("{d}:{s: <4}", .{ line, "", });
        }
    }
    std.debug.print("\n\n", .{});

    var parser = Parser.init(bufalloc.allocator(), &stream);
    const ast = parser.parse() catch {

        for (parser.errors.items) |err| {
            
            const ref = try SourceRef.new(
                buffer,
                err.begin orelse buffer.len - 1,
                err.end   orelse buffer.len,
            );

            std.debug.print("Error on line {d}: ", .{ ref.line, });

            switch (err.kind) {
                .expected_token => |e| {
                    std.debug.print("Expected {s}, found {s}.",
                        .{
                            @tagName(e.expected),
                            if (e.found) |found| @tagName(found) else "end of input",
                        },
                    );
                },
                .expected_token_range => |e| {
                    std.debug.print("Expected one of ", .{});
                    for (e.expected) |expected| {
                        std.debug.print("{s}, ", .{ @tagName(expected), });
                    }
                    std.debug.print("found {s}\n", .{
                        if (e.found) |found| @tagName(found) else "end of input",
                    });
                },
                .unexpected_eoi => {
                    std.debug.print("Unexpected end of input\n", .{});
                },
            }

            std.debug.print("{s}\n", .{ ref.view, });
            for (0..ref.begin) |_| std.debug.print(" ", .{});
            for (0..(ref.end - ref.begin)) |_| std.debug.print("^", .{});
            std.debug.print("\n", .{});
        }

        return;
    };

    @import("ast.zig").print(buffer, parser.nodes.items, ast);
}
