
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

const rc = std.enums.values(Register).len;

const State = union(enum) {
    unused,
    result,
    symbol: usize,
};

const Allocation = struct {
    register: Register,
    spilled:  ?usize = null,
    load:     bool = false,
};

registers: [rc] State,
next: usize,

pub fn init() Self {
    return .{
        .registers = [_] State {.unused} ** rc,
        .next      = 0,
    };
}

pub fn reset(self: *Self) void {
    self.* = Self.init();
}

pub fn alloc(self: *Self, symbol: ?usize) !Allocation {

    // May already be allocated
    if (symbol) |s| {
        for (0..rc) |i_| {
            const i = (i_ + self.next) % rc;
            const register: Register = @enumFromInt(i);
            if (register == .none) {
                continue;
            }
            const state = &self.registers[i];
            switch (state.*) {
                .symbol => |v| if (s == v) {
                     self.next = (i + 1) % rc;
                     return .{ .register = register, };
                },
                else => continue,
            }
        }
    }
    
    // Find unused
    for (0..rc) |i_| {
        const i = (i_ + self.next) % rc;
        const register: Register = @enumFromInt(i);
        if (register == .none) {
            continue;
        }
        const state = &self.registers[i];
        switch (state.*) {
            .unused => {
                 self.next = (i + 1) % rc;
                 if (symbol) |s| {
                     state.* = .{ .symbol = s };
                     return .{ .register = register, .load = true, };
                 } else {
                     state.* = .result;
                     return .{ .register = register, };
                 }
            },
            else => continue,
        }
    }

    // Find variable to spill
    for (0..rc) |i_| {
        const i = (i_ + self.next) % rc;
        const register: Register = @enumFromInt(i);
        if (register == .none) {
            continue;
        }
        const state = & self.registers[i];
        switch (state.*) {
            .symbol => |spilled| {
                if (symbol) |s| {
                    state.* = .{ .symbol = s, };
                } else {
                    state.* = .result;
                }
                self.next = (i + 1) % rc;
                return .{
                    .register = register,
                    .spilled = spilled,
                    .load = if (symbol) |_| true else false,
                };
            },
            else => continue,
        }
    }

    // Only results in registers, we don't wanna touch those
    return error.RegisterAllocationError;
}

pub fn free(self: *Self, register: Register) void {

    self.registers[@intFromEnum(register)] = .unused;
}

pub fn freeIfResult(self: *Self, register: Register) void {

    const register_ref = &self.registers[@intFromEnum(register)];
    
    switch (register_ref.*) {
        .result => register_ref.* = .unused,
        else => {},
    }
}

pub fn isResult(self: *Self, register: Register) bool {
    
    return switch (self.registers[@intFromEnum(register)]) {
        .result => true,
        else => false,
    };
}
