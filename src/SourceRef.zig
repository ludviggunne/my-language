
const std = @import("std");

const Self = @This();

view:  []const u8,
line:  usize,
begin: usize,
end:   usize,

pub fn new(source: []const u8, refbegin: usize, refend: usize) !Self {

    if (refend > source.len or refbegin >= refend) {
        return error.IndexOutOfRange;
    }

    var begin: usize = 0;
    var line: usize = 1;
    for (source, 0..) |c, i| {

        if (c == '\n') {
            line += 1;
            begin = if (i < source.len - 1) i + 1 else i;
        }

        if (i == refbegin) {

            var end: usize = undefined;

            for (source[begin..], begin..) |d, j| {

                if (d == '\n') {
                    end = j;
                    break;
                }
            } else end = source.len;

            return .{
                .view  = source[begin..end],
                .line  = line,
                .begin = refbegin - begin,
                .end   = refend - begin,
            };
        }
    }

    unreachable;
}
