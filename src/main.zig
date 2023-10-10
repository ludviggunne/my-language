
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
    const file = try cwd.openFile("./program.l", .{});
    const buffer = try file.readToEndAlloc(bufalloc.allocator(), 1024);

    // Lex file
    var lexer = Lexer.init(buffer);
    var parser = Parser.init(bufalloc.allocator(), &lexer);
    const ast = parser.parse() catch {

        for (parser.errors.items) |err| {
            try errors.reportParseError(err, stdout, buffer);            
        }

        return;
    };

    var codegen = CodeGen.init(&ast, bufalloc.allocator(), buffer);
    codegen.initWriters();
    codegen.generate() catch {

        for (codegen.errors.items) |err| {
            try errors.reportCodeGenError(err, stdout, buffer);
        }

        return;
    };

    var output = try cwd.createFile("./output.S", .{});
    var out_writer = output.writer();
    try codegen.output(&out_writer);
}
