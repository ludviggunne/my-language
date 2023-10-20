
const std = @import("std");

const Lexer          = @import("Lexer.zig");
const Ast            = @import("Ast.zig");
const Parser         = @import("Parser.zig");
const TypeChecker    = @import("TypeChecker.zig");
const ConstantFolder = @import("ConstantFolder.zig");
const SymbolTable    = @import("SymbolTable.zig");
const CodeGen        = @import("CodeGen.zig");

pub fn main() !u8 {

    const dump = true;

    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const cwd = std.fs.cwd();
    const file = try cwd.openFile("./program.l", .{});
    const source = try file.readToEndAlloc(allocator, 2048);
    defer allocator.free(source);
    file.close();

    var lexer = Lexer.init(source, allocator); 
    defer lexer.deinit();

    if (dump) {
        try lexer.dump(stdout);
        lexer.reset();
    }

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
    if (dump) try ast.dump(stdout, allocator);

    // Typecheck
    var type_checker = TypeChecker.init(&ast, allocator);
    defer type_checker.deinit();
    type_checker.check() catch {

        for (type_checker.errors.items) |err| {
            try err.print(source, stdout);
        }

        return 1;
    };

    // Constant folding
    var folder = ConstantFolder.init(&ast, allocator);
    defer folder.deinit();

    folder.fold() catch {

        for (folder.errors.items) |err| {
            try err.print(source, stdout);
        }

        return 1;
    };
    
    if (dump) try ast.dump(stdout, allocator);

    // Symbol resolution
    var symtab = try SymbolTable.init(&ast, allocator);
    defer symtab.deinit();

    symtab.resolve() catch {

        for (symtab.errors.items) |err| {
            try err.print(source, stdout);
        }

        return 1;
    };

    if (dump) try symtab.dump(stdout);

    // Codegen
    var output_file = try cwd.createFile("./output.S", .{});
    var output = output_file.writer();

    var codegen = CodeGen.init(&ast, &symtab, allocator);
    defer codegen.deinit();
    codegen.generate(output) catch {

        for (codegen.errors.items) |err| {
            try err.print(source, stdout);
        }

        return 1;
    };

    return 0;
}
