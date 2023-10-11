
const std = @import("std");

const Self = @This();

pub const Register = enum {
    none,
    r10,
    r11,
    r12,
    r13,
    r14,
    r15,
};

in_use: std.EnumSet(Register),

pub fn init() Self {

    return .{
        .in_use = std.EnumSet(Register).initEmpty(),
    };
}

pub fn allocate(self: *Self) !Register {
    
    for (std.enums.values(Register)) |reg| {

        if (reg == .none) continue;

        if (!self.in_use.contains(reg)) {
            
            self.in_use.insert(reg);
            return reg;
        }
    }

    return error.MaxCapacity;
}

pub fn deallocate(self: *Self, register: Register) void {

    self.in_use.remove(register);
}
