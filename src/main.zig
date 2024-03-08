const std = @import("std");

const Lexer = @import("Lexer.zig");
const Ast = @import("Ast.zig");
const Parser = @import("Parser.zig");
const TypeChecker = @import("TypeChecker.zig");
const ConstantFolder = @import("ConstantFolder.zig");
const SymbolTable = @import("SymbolTable.zig");
const CodeGen = @import("CodeGen.zig");
const Config = @import("Config.zig");
const Error = @import("Error.zig");

pub fn main() !u8 {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = Config.init(allocator);
    defer config.deinit();
    config.parse(args) catch try Error.printErrorsAndExit(&config, "", stdout);

    const cwd = std.fs.cwd();
    const file = cwd.openFile(config.input, .{}) catch try {
        try stdout.print("Error: Couldn't open source file {0s}\n", .{
            config.input,
        });
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
    var parser = Parser.init(&lexer, &ast, allocator);
    defer parser.deinit();

    parser.parse() catch try Error.printErrorsAndExit(&parser, source, stdout);

    if (config.dump) try ast.dump(stdout, allocator);

    // Symbol resolution
    var symtab = try SymbolTable.init(&ast, allocator);
    defer symtab.deinit();

    symtab.resolve() catch try Error.printErrorsAndExit(&symtab, source, stdout);

    // Typecheck
    var type_checker = TypeChecker.init(&ast, &symtab, allocator);
    defer type_checker.deinit();
    type_checker.check() catch try Error.printErrorsAndExit(&type_checker, source, stdout);

    if (config.dump) try symtab.dump(stdout);

    // Constant folding
    var folder = ConstantFolder.init(&ast, &symtab, allocator);
    defer folder.deinit();

    folder.fold() catch try Error.printErrorsAndExit(&folder, source, stdout);

    // Codegen
    var output_file = cwd.createFile("./asm.S", .{}) catch {
        try stdout.print("Error: Couldn't create intermediate assembly file\n", .{});
        return 1;
    };
    const output = output_file.writer();

    // Generate assembly
    var codegen = CodeGen.init(&ast, &symtab, allocator);
    defer codegen.deinit();
    codegen.generate(output) catch try Error.printErrorsAndExit(&codegen, source, stdout);

    // Invoke gcc
    const gcc_args = [_][]const u8{
        "gcc",
        "./asm.S",
        "-o",
        config.output,
    };
    var gcc = std.process.Child.init(&gcc_args, allocator);
    try gcc.spawn();
    _ = try gcc.wait();

    // Clean up
    if (config.remove_assembly) {
        const rm_args = [_][]const u8{
            "rm",
            "./asm.S",
        };
        var rm = std.process.Child.init(&rm_args, allocator);
        try rm.spawn();
        _ = try rm.wait();
    }

    return 0;
}
