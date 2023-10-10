
const std = @import("std");

const Self = @This();

map: std.StringHashMap(usize),
counter: usize, 

pub fn init(allocator: std.mem.Allocator) Self {

    return .{

        .map = std.StringHashMap(usize).init(allocator),
        .counter = 0,
    };
}

pub fn get(self: *Self, string: []const u8) ?usize {

    return self.map.get(string);
}

pub fn getDeclare(self: *Self, string: []const u8) !usize {

    if (self.map.get(string)) |id| {
        return id;
    } else {
        defer self.counter += 1;
        errdefer self.counter -= 1;
        try self.map.put(string, self.counter);
        return self.counter;
    }
}

pub fn deinit(self: *Self) void {

    self.map.deinit();
}
