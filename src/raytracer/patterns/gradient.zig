const std = @import("std");
const testing = std.testing;
const Tuple = @import("../tuple.zig").Tuple;
const Color = @import("../color.zig").Color;
const Pattern = @import("pattern.zig").Pattern;

/// A gradient pattern, backed by floats of type `T`.
///
/// This is a higher-order pattern, meaning the gradient
/// itself may transition between two complex patterns.
///
/// The gradient transition is governed only by the x
/// coordinate in pattern space. To transform the pattern, use
/// `Pattern.setTransform`.
pub fn GradientPattern(comptime T: type) type {
    return struct {
        const Self = @This();

        // a and b must live at least as long as the struct
        a: *const Pattern(T),
        b: *const Pattern(T),

        pub fn new(a: *const Pattern(T), b: *const Pattern(T)) Self {
            return .{ .a = a, .b = b };
        }

        pub fn patternAt(self: Self, pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
            const fpart = pattern_point.x - @floor(pattern_point.x);
            const a_color = self.a.patternAt(object_point);
            const b_color = self.b.patternAt(object_point);
            return a_color.add(b_color.sub(a_color).mul(fpart));
        }
    };
}

test "GradientPattern" {
    const white = Color(f32).new(1.0, 1.0, 1.0);
    const black = Color(f32).new(0.0, 0.0, 0.0);
    const solid_white = Pattern(f32).solid(white);
    const solid_black = Pattern(f32).solid(black);
    const pattern = GradientPattern(f32).new(&solid_white, &solid_black);

    // placeholder
    const o = Tuple(f32).point(0.0, 0.0, 0.0);

    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 0.0), o),
                            white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.25, 0.0, 0.0), o),
                            Color(f32).new(0.75, 0.75, 0.75));
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.5, 0.0, 0.0), o),
                            Color(f32).new(0.5, 0.5, 0.5));
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.75, 0.0, 0.0), o),
                            Color(f32).new(0.25, 0.25, 0.25));
}
