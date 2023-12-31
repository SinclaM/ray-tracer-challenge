const std = @import("std");
const testing = std.testing;
const Tuple = @import("../tuple.zig").Tuple;
const Color = @import("../color.zig").Color;
const Pattern = @import("pattern.zig").Pattern;

/// A pattern of concentric rings, backed by floats of type `T`.
///
/// This is a higher-order pattern, meaning the rings
/// themselves may contain complex patterns.
///
/// The rings are always centered on the origin and independent
/// of y in pattern space. To transform the pattern, use
/// `Pattern.setTransform`.
pub fn Rings(comptime T: type) type {
    return struct {
        const Self = @This();

        // a and b must live at least as long as the struct
        a: *const Pattern(T),
        b: *const Pattern(T),

        pub fn new(a: *const Pattern(T), b: *const Pattern(T)) Self {
            return .{ .a = a, .b = b };
        }

        pub fn patternAt(self: Self, pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
            if (@mod(@floor(@sqrt(pattern_point.x * pattern_point.x + pattern_point.z * pattern_point.z)), 2.0) < 1.0) {
                return self.a.patternAt(object_point);
            } else{
                return self.b.patternAt(object_point);
            }
        }
    };
}

test "Rings" {
    const white = Color(f32).new(1.0, 1.0, 1.0);
    const black = Color(f32).new(0.0, 0.0, 0.0);
    const solid_white = Pattern(f32).solid(white);
    const solid_black = Pattern(f32).solid(black);
    const pattern = Rings(f32).new(&solid_white, &solid_black);

    // placeholder
    const o = Tuple(f32).point(0.0, 0.0, 0.0);

    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 0.0), o), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(1.0, 0.0, 0.0), o), black);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 1.0), o), black);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.708, 0, 0.708), o), black);
}
