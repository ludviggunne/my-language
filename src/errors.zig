
// TODO: refactor

const SourceRef   = @import("SourceRef.zig");
const Parser      = @import("Parser.zig");
const CodeGen     = @import("CodeGen.zig");
const SymbolTable = @import("SymbolTable.zig");

pub fn reportParseError(err: Parser.Error, writer: anytype, source: []const u8) !void {

    const ref = try SourceRef.new(
        source,
        err.begin orelse source.len - 1,
        err.end   orelse source.len,
    );

    try writer.print("Error on line {d}:\n", .{ ref.line, });

    switch (err.kind) {
        .expected_token => |e| {
            try writer.print(
                \\    Expected {s}
                \\    Found {s}
                \\
                , .{
                    @tagName(e.expected),
                    if (e.found) |found| @tagName(found) else "end of input",
                },
            );
        },
        .expected_token_range => |e| {
            try writer.print("    Expected one of ", .{});
            for (e.expected) |expected| {
                try writer.print("{s}, ", .{ @tagName(expected), });
            }
            try writer.print("\n    found {s}\n", .{
                if (e.found) |found| @tagName(found) else "end of input",
            });
        },
        .unexpected_eoi => {
            try writer.print("    Unexpected end of input\n", .{});
        },
    }

    try writer.print("{s}\n", .{ ref.view, });
    for (0..ref.begin) |_| try writer.print(" ", .{});
    for (0..(ref.end - ref.begin)) |_| try writer.print("^", .{});
    try writer.print("\n", .{});
}

pub fn reportSymbolResolutionError(err: SymbolTable.Error, writer: anytype, source: []const u8) !void {

    const ref = try SourceRef.new(
        source,
        err.begin,
        err.end,
    );

    try writer.print("Error on line {d}:\n", .{ ref.line, });

    switch (err.kind) {
        .redeclaration => try writer.print(
            "    Redeclaration of symbol {s}\n",
            .{ source[err.begin..err.end], },
        ),
        .undeclared => try writer.print(
            "    Reference to undeclared symbol {s}\n",
            .{ source[err.begin..err.end], },
        ),
    }

    try writer.print("{s}\n", .{ ref.view, });
    for (0..ref.begin) |_| try writer.print(" ", .{});
    for (0..(ref.end - ref.begin)) |_| try writer.print("^", .{});
    try writer.print("\n", .{});
}
