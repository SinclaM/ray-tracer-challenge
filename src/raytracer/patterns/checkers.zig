const std = @import("std");
const testing = std.testing;
const Tuple = @import("../tuple.zig").Tuple;
const Color = @import("../color.zig").Color;
const Pattern = @import("pattern.zig").Pattern;

/// A 3D checker-board pattern, backed by floats of type `T`.
///
/// This is a higher-order pattern, meaning the checkered areas
/// may themselves be complex patterns.
pub fn Checkers(comptime T: type) type {
    return struct {
        const Self = @This();

        // a and b must live at least as long as the struct
        a: *const Pattern(T),
        b: *const Pattern(T),

        pub fn new(a: *const Pattern(T), b: *const Pattern(T)) Self {
            return .{ .a = a, .b = b };
        }

        pub fn patternAt(self: Self, pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
            if (@mod(@floor(pattern_point.x) + @floor(pattern_point.y) + @floor(pattern_point.z), 2.0) < 1.0) {
                return self.a.patternAt(object_point);
            } else {
                return self.b.patternAt(object_point);
            }
        }
    };
}

test "Checkers" {
    const white = Color(f32).new(1.0, 1.0, 1.0);
    const black = Color(f32).new(0.0, 0.0, 0.0);
    const solid_white = Pattern(f32).solid(white);
    const solid_black = Pattern(f32).solid(black);
    const pattern = Checkers(f32).new(&solid_white, &solid_black);

    // placeholder
    const o = Tuple(f32).point(0.0, 0.0, 0.0);

    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 0.0), o), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.99, 0.0, 0.0), o), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(1.01, 0.0, 0.0), o), black);

    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 0.0), o), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.99, 0.0), o), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 1.01, 0.0), o), black);

    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 0.0), o), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 0.99), o), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 1.01), o), black);
}
