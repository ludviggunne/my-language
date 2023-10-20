
const std = @import("std");

const Lexer          = @import("Lexer.zig");
const Ast            = @import("Ast.zig");
const Parser         = @import("Parser.zig");
const TypeChecker    = @import("TypeChecker.zig");
const ConstantFolder = @import("ConstantFolder.zig");
const SymbolTable    = @import("SymbolTable.zig");
const CodeGen        = @import("CodeGen.zig");
const Config         = @import("Config.zig");

pub fn main() !u8 {

    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = Config.init(allocator);
    defer config.deinit();
    config.parse(args) catch {

        for (config.errors.items) |err| {
            try err.print("", stdout);
        }

        return 1;
    };

    const cwd = std.fs.cwd();
    const file = cwd.openFile(config.input, .{}) catch {
        try stdout.print("Error: Couldn't open source file {0s}\n", .{ config.input, });
        return 1;
    };
    const source = try file.readToEndAlloc(allocator, 2048);
    defer allocator.free(source);
    file.close();

    var lexer = Lexer.init(source, allocator); 
    defer lexer.deinit();

    if (config.dump) {
        try lexer.dump(stdout);
        lexer.reset();
    }

    var ast = Ast.init(allocator);
    defer ast.deinit();

    // Parse
    try stdout.print("Parsing...\n", .{});
    var parser = Parser.init(&lexer, &ast, allocator);
    defer parser.deinit();

    parser.parse() catch {
        
        for (parser.errors.items) |*err| {
            try err.print(source, stdout);
        }

        return 1;
    };
    if (config.dump) try ast.dump(stdout, allocator);

    // Typecheck
    try stdout.print("Type checking...\n", .{});
    var type_checker = TypeChecker.init(&ast, allocator);
    defer type_checker.deinit();
    type_checker.check() catch {

        for (type_checker.errors.items) |err| {
            try err.print(source, stdout);
        }

        return 1;
    };

    // Constant folding
    try stdout.print("Folding constant expressions...\n", .{});
    var folder = ConstantFolder.init(&ast, allocator);
    defer folder.deinit();

    folder.fold() catch {

        for (folder.errors.items) |err| {
            try err.print(source, stdout);
        }

        return 1;
    };
    
    if (config.dump) try ast.dump(stdout, allocator);

    // Symbol resolution
    try stdout.print("Resolving symbols...\n", .{});
    var symtab = try SymbolTable.init(&ast, allocator);
    defer symtab.deinit();

    symtab.resolve() catch {

        for (symtab.errors.items) |err| {
            try err.print(source, stdout);
        }

        return 1;
    };

    if (config.dump) try symtab.dump(stdout);

    // Codegen
    var output_file = cwd.createFile("./asm.S", .{}) catch {
        try stdout.print("Error: Couldn't create intermediate assembly file\n", .{});
        return 1;
    };
    var output = output_file.writer();

    try stdout.print("Generating assembly...\n", .{});
    var codegen = CodeGen.init(&ast, &symtab, allocator);
    defer codegen.deinit();
    codegen.generate(output) catch {

        for (codegen.errors.items) |err| {
            try err.print(source, stdout);
        }

        return 1;
    };

    // Invoke gcc
    try stdout.print("Invoking gcc...\n", .{});
    const gcc_args = [_][] const u8 { "gcc", "./asm.S", "-o", config.output, };
    var gcc = std.process.Child.init(&gcc_args, allocator);
    try gcc.spawn();
    _ = try gcc.wait(); // TODO: Handle return code

    // Clean up
    const rm_args = [_][] const u8 { "rm", "./asm.S", };
    var rm = std.process.Child.init(&rm_args, allocator);
    try rm.spawn();
    _ = try rm.wait();

    try stdout.print("Compilation complete!\n", .{});

    return 0;
}
