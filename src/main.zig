
const std       = @import("std");

const Lexer       = @import("Lexer.zig");
const Parser      = @import("Parser.zig");
const SourceRef   = @import("SourceRef.zig");
const errors      = @import("errors.zig");
const CodeGen     = @import("CodeGen.zig");
const SymbolTable = @import("SymbolTable.zig");

pub fn main() !void {

    const stdout = std.io.getStdOut().writer();

    // Read file
    var alloc = std.heap.GeneralPurposeAllocator(.{}) {};
    const cwd = std.fs.cwd();
    const file = try cwd.openFile("./program.l", .{});
    const source = try file.readToEndAlloc(alloc.allocator(), 1024);

    // Lex file
    var lexer = Lexer.init(source);

    // Parse file
    var parser = Parser.init(alloc.allocator(), &lexer);
    var ast = parser.parse() catch {

        for (parser.errors.items) |err| {
            try errors.reportParseError(err, stdout, source);            
        }

        return;
    };

    //@import("ast.zig").print(source, &ast);

    // Create symbol table
    var symtab = try SymbolTable.init(alloc.allocator(), &ast, source);
    symtab.resolve() catch {

        for (symtab.errors.items) |err| {
            try errors.reportSymbolResolutionError(err, stdout, source);
        }

        return;
    };

    // Generate assembly
    var codegen = CodeGen.init(&ast, alloc.allocator(), &symtab);
    codegen.initWriters();
    try codegen.generate();

    var output = try cwd.createFile("./output.S", .{});
    var out_writer = output.writer();
    try codegen.output(&out_writer);
}
