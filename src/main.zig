
const std         = @import("std");
const Lexer       = @import("Lexer.zig");
const Parser      = @import("Parser.zig");
const SourceRef   = @import("SourceRef.zig");
const errors      = @import("errors.zig");
const CodeGen     = @import("CodeGen.zig");
const SymbolTable = @import("SymbolTable.zig");

pub fn main() !u8 {

    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    // Read file
    const cwd = std.fs.cwd();
    const file = try cwd.openFile("./program.l", .{});
    const source = try file.readToEndAlloc(alloc, 1024);
    defer alloc.free(source);
    file.close();

    // Lex file
    var lexer = Lexer.init(source);

    // Parse file
    var parser = Parser.init(alloc, &lexer);
    defer parser.deinit();

    var ast = parser.parse() catch {

        for (parser.errors.items) |err| {
            try errors.reportParseError(err, stdout, source);            
        }

        return 1;
    };

    //@import("ast.zig").print(source, &ast);

    // Create symbol table
    var symtab = try SymbolTable.init(alloc, &ast, source);
    defer symtab.deinit();

    symtab.resolve() catch {

        for (symtab.errors.items) |err| {
            try errors.reportSymbolResolutionError(err, stdout, source);
        }

        return 1;
    };

    // Generate assembly
    var codegen = CodeGen.init(&ast, alloc, &symtab);
    defer codegen.deinit();

    codegen.initWriters();
    try codegen.generate();

    // Output
    var output = try cwd.createFile("./output.S", .{});
    var out_writer = output.writer();
    try codegen.output(&out_writer);

    return 0;
}
