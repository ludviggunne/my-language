
const std = @import("std");

const TokenKind = @import("../token.zig").TokenKind;
const NonTerm = @import("nonterm.zig").NonTerm;
const grammar = @import("grammar.zig").grammar;

pub const first = First.init();

pub const First = struct {

    const Self = @This();
    const Data = std.EnumArray(
        NonTerm,
        ?std.EnumSet(TokenKind) 
    );

    data: Data,

    pub fn init() Self {

        var f: Self = .{
            .data = Data.initFill(null),
        };

        f.computeAll();
        return f;
    }

    // Get FIRST set of non-terminal
    pub fn get(self: *const Self, nonterm: NonTerm) *const std.EnumSet(TokenKind) {
        return &(self.data.getPtrConst(nonterm).*.?);
    }

    // Compute all FIRST sets
    pub fn computeAll(self: *Self) void {

        for (std.enums.values(NonTerm)) |nonterm| {
            self.compute(nonterm); 
        }
    }

    // Compute FIRST for non-terminal nonterm
    pub fn compute(self: *Self, nonterm: NonTerm) void {

        if (self.data.get(nonterm)) |_| {
            // Already computed
            return;
        }

        self.data.set(nonterm, std.EnumSet(TokenKind).initEmpty());
        const set = &(self.data.getPtr(nonterm).*.?);

        for (grammar) |rule| {
            if (rule.left == nonterm) {
                switch (rule.right[0]) {

                    // If first symbol of right hand is terminal
                    //  add said terminal to FIRST
                    .term => |t| set.insert(t),

                    // If it is non-terminal, we add said
                    //  non-terminals FIRST to this FIRST        
                    .nonterm => |nt| {

                        // Compute other set if ont yet computed
                        if (self.data.get(nt) == null) {
                            self.compute(nt);
                        }

                        const other = self.data.getPtr(nt);
                        set.setUnion(other.*.?);
                    },
                }
            }
        }
    }
};
