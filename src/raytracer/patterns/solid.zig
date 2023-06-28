const std = @import("std");
const testing = std.testing;
const Tuple = @import("../tuple.zig").Tuple;
const Color = @import("../color.zig").Color;

/// A pattern of just one color.
///
/// This pattern is useless on its own, but can form the
/// base pattern for other higher-order patterns.
pub fn SolidPattern(comptime T: type) type {
    return struct {
        const Self = @This();

        a: Color(T),

        pub fn new(a: Color(T)) Self {
            return .{ .a = a };
        }

        pub fn patternAt(self: Self, pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
            _ = pattern_point;
            _ = object_point;
            return self.a;
        }
    };
}

test "SolidPattern" {
    const white = Color(f32).new(1.0, 1.0, 1.0);
    const pattern = SolidPattern(f32).new(white);

    // placeholder
    const o = Tuple(f32).point(0.0, 0.0, 0.0);

    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 0.0), o), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.9, 0.0, 0.0), o), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.9, 0.0), o), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-100.0, 0.0, 12.0), o), white);
}
