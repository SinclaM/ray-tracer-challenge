const std = @import("std");
const testing = std.testing;
const Tuple = @import("../tuple.zig").Tuple;
const Color = @import("../color.zig").Color;

pub fn StripesPattern(comptime T: type) type {
    return struct {
        const Self = @This();

        a: Color(T),
        b: Color(T),

        pub fn new(a: Color(T), b: Color(T)) Self {
            return .{ .a = a, .b = b };
        }

        pub fn patternAt(self: Self, pattern_point: Tuple(T)) Color(T) {
            return if (@mod(pattern_point.x, 2.0) < 1.0) self.a else self.b;
        }
    };
}

test "StripesPattern" {
    const white = Color(f32).new(1.0, 1.0, 1.0);
    const black = Color(f32).new(0.0, 0.0, 0.0);
    const pattern = StripesPattern(f32).new(white, black);

    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 0.0)), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.9, 0.0, 0.0)), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(1.0, 0.0, 0.0)), black);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-0.1, 0.0, 0.0)), black);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-1.0, 0.0, 0.0)), black);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-1.1, 0.0, 0.0)), white);
}
