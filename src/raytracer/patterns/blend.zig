const std = @import("std");
const testing = std.testing;
const pi = std.math.pi;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Color = @import("../color.zig").Color;
const Pattern = @import("pattern.zig").Pattern;

/// A pattern that blends two other patterns,
/// backed by floats of type `T`.
pub fn Blend(comptime T: type) type {
    return struct {
        const Self = @This();

        // a and b must live at least as long as the struct
        a: *const Pattern(T),
        b: *const Pattern(T),

        pub fn new(a: *const Pattern(T), b: *const Pattern(T)) Self {
            return .{ .a = a, .b = b };
        }

        pub fn patternAt(self: Self, pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
            _ = pattern_point;
            return self.a.patternAt(object_point).add(self.b.patternAt(object_point)).mul(0.5);
        }
    };
}

test "Blend" {
    const white = Color(f32).new(1.0, 1.0, 1.0);
    const black = Color(f32).new(0.0, 0.0, 0.0);
    const solid_white = Pattern(f32).solid(white);
    const solid_black = Pattern(f32).solid(black);

    const stripes = Pattern(f32).stripes(&solid_white, &solid_black);
    var rotated_stripes = Pattern(f32).stripes(&solid_white, &solid_black);
    try rotated_stripes.setTransform(Matrix(f32, 4).identity().rotateY(pi / 2.0));
    const pattern = Pattern(f32).blend(&stripes, &rotated_stripes);

    const gray = Color(f32).new(0.5, 0.5, 0.5);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.0, 0.0, 0.0)), white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.5, 0.0, 0.5)), gray);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-0.5, 0.0, 0.5)), black);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-0.5, 0.0, -0.5)), gray);
}
