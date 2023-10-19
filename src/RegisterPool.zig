
const std = @import("std");
const Self = @This();

pub const Register = enum {
    none,
    r8,
    r9,
    r10,
    r11,
    r12,
    r13,
    r14,
    r15,
};

in_use: std.EnumSet(Register),

pub fn init() Self {
    return .{ .in_use= std.EnumSet(Register).initEmpty(), };
}

pub fn reset(self: *Self) void {
    self.* = Self.init();
}

pub fn alloc(self: *Self) !Register {
    
    for (std.enums.values(Register)[1..]) |register| {

        if (!self.in_use.contains(register)) {
            self.in_use.insert(register);
            return register;
        }
    }

    return error.RegisterAllocationError;
}

pub fn free(self: *Self, register: Register) void {

    self.in_use.remove(register);
}
