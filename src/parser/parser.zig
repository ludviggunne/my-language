
usingnamespace @import("lexer.zig");

pub const NonTerminal = enum {
    expression,
    term,
    factor,
    literal,
    identifier,
};

pub const Node = struct {
    
    left:  ?*Node,
    right: ?*Node,
    token: ?Token,

    kind: enum {
        binary,
        unary, 
        atomic,
    },
};

pub const Parser = struct {

    const Self = @This();
    pub const Error = enum {
        unexpected_token, 
    };

    lexer: Lexer,
    err_location: ?[]const u8,
    nodes: *std.ArrayList(Node),

    pub fn init(lexer: Lexer, nodes: *std.ArrayList(Node)) Self {

        return .{
            .lexer = lexer,
            .err_location = null,
            .nodes = nodes,
        };
    }
    
    pub fn parse(self: *Self, comptime nt: NonTerminal) Error!*Node {
        
        switch (nt) {
            
            .expression => {

            },
        } 
    }

    fn expect(self: *Self, token: TokenKind) Error!void {
        
        if (self.lexer.next()) |next| {
            if (next == token.kind) return;
        }
        
        self.err_location = token.loc;
        return Error.unexpected_token;
    }

    fn new_node(self: *Self) *Node {
        
        return self.nodes.addOne() catch unreachable;
    }
};
