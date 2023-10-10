
const std       = @import("std");

const Lexer     = @import("Lexer.zig");
const Parser    = @import("Parser.zig");
const SourceRef = @import("SourceRef.zig");
const errors    = @import("errors.zig");
const CodeGen   = @import("CodeGen.zig");

pub fn main() !void {

    const stdout = std.io.getStdOut().writer();

    // Read file
    var bufalloc = std.heap.GeneralPurposeAllocator(.{}) {};
    const cwd = std.fs.cwd();
    const file = try cwd.openFile("./test.l", .{});
    const buffer = try file.readToEndAlloc(bufalloc.allocator(), 1024);

    // Lex file
    var lexer = Lexer.init(buffer);

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

    var parser = Parser.init(bufalloc.allocator(), &lexer);
    const ast = parser.parse() catch {

        for (parser.errors.items) |err| {
            try errors.reportParseError(err, stdout, buffer);            
        }

        return;
    };

    @import("ast.zig").print(buffer, &ast);

    std.debug.print("\n\n", .{});

    var codegen = CodeGen.init(&ast, bufalloc.allocator(), buffer);
    codegen.initWriters();
    try codegen.generate();

    var output = try cwd.createFile("./output.S", .{});
    var out_writer = output.writer();
    try codegen.output(&stdout);
    try codegen.output(&out_writer);
}
