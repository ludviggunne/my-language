
const Self = @This();

const std = @import("std");

const Error = @import("Error.zig");

input:  []const u8,
output: []const u8,
dump:   bool,
errors: std.ArrayList(Error),

pub fn init(allocator: std.mem.Allocator) Self {

    return .{
        .input = "UNSPECIFIED",
        .output = "program",
        .dump = false,
        .errors = std.ArrayList(Error).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.errors.deinit();
}

pub fn parse(self: *Self, args: [][:0] u8,) !void {
    
    if (args.len == 1) {
        try self.errors.append(.{
            .stage = .command_line_parsing,
            .kind = .no_input_file,
        });
        return error.ConfigError;
    }

    self.input = args[1];

    if (args.len == 2) return;

    var args_slice = args[2..];

    while (args_slice.len > 0) {

        const first = args_slice[0];
        if (std.mem.eql(u8, first, "-o")) {

            if (args_slice.len == 1) {
                try self.errors.append(.{
                    .stage = .command_line_parsing,
                    .kind = .{ .expected_arg = first, },
                });
            }

            self.output = args_slice[1];            

            if (args_slice.len == 2) return;
            
            args_slice = args_slice[2..];
            continue;
        }

        if (std.mem.eql(u8, first, "-d")) {

            self.dump = true;
            args_slice = args_slice[1..];
            continue;
        }

        try self.errors.append(.{
            .stage = .command_line_parsing,
            .kind = .{ .invalid_option = first, },
        });
        return error.ConfigError;
    }
}
