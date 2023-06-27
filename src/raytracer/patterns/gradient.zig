const std = @import("std");
const testing = std.testing;
const Tuple = @import("../tuple.zig").Tuple;
const Color = @import("../color.zig").Color;

pub fn GradientPattern(comptime T: type) type {
    return struct {
        const Self = @This();

        a: Color(T),
        b: Color(T),

        pub fn new(a: Color(T), b: Color(T)) Self {
            return .{ .a = a, .b = b };
        }

        pub fn patternAt(self: Self, pattern_point: Tuple(T)) Color(T) {
            const fpart = pattern_point.x - @floor(pattern_point.x);
            return self.a.add(self.b.sub(self.a).mul(fpart));
        }
    };
}

test "GradientPattern" {
    const white = Color(f32).new(1.0, 1.0, 1.0);
    const black = Color(f32).new(0.0, 0.0, 0.0);
    const pattern = GradientPattern(f32).new(white, black);

    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 0.0)),
                            white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.25, 0.0, 0.0)),
                            Color(f32).new(0.75, 0.75, 0.75));
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.5, 0.0, 0.0)),
                            Color(f32).new(0.5, 0.5, 0.5));
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.75, 0.0, 0.0)),
                            Color(f32).new(0.25, 0.25, 0.25));
}
