const std = @import("std");
const testing = std.testing;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Color = @import("../color.zig").Color;
const Shape = @import("../shapes/shape.zig").Shape;
const StripesPattern = @import("stripes.zig").StripesPattern;
const GradientPattern = @import("gradient.zig").GradientPattern;
const RingsPattern = @import("rings.zig").RingsPattern;
const CheckersPattern = @import("checkers.zig").CheckersPattern;

pub fn Pattern(comptime T: type) type {
    return struct {
        const Self = @This();

        const Variant = union(enum) {
            test_pattern: TestPattern(T),
            stripes: StripesPattern(T),
            gradient: GradientPattern(T),
            rings: RingsPattern(T),
            checkers: CheckersPattern(T),
        };

        _transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        _inverse_transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        variant: Variant,

        fn new(variant: Variant) Self {
            return .{ .variant = variant };
        }

        pub fn testPattern() Self {
            return Self.new(Self.Variant { .test_pattern = TestPattern(T).new() });
        }

        pub fn stripes(a: Color(T), b: Color(T)) Self {
            return Self.new(Self.Variant { .stripes = StripesPattern(T).new(a, b) });
        }

        pub fn gradient(a: Color(T), b: Color(T)) Self {
            return Self.new(Self.Variant { .gradient = GradientPattern(T).new(a, b) });
        }

        pub fn rings(a: Color(T), b: Color(T)) Self {
            return Self.new(Self.Variant { .rings = RingsPattern(T).new(a, b) });
        }

        pub fn checkers(a: Color(T), b: Color(T)) Self {
            return Self.new(Self.Variant { .checkers = CheckersPattern(T).new(a, b) });
        }

        pub fn setTransform(self: *Self, matrix: Matrix(T, 4)) !void {
            self._transform = matrix;
            self._inverse_transform = try matrix.inverse();
        }

        pub fn patternAtShape(self: Self, shape: Shape(T), world_point: Tuple(T)) Color(T) {
            const object_point = shape._inverse_transform.tupleMul(world_point);
            const pattern_point = self._inverse_transform.tupleMul(object_point);

            switch (self.variant) {
                inline else => |s| { return s.patternAt(pattern_point); },
            }
        }
    };
}

fn TestPattern(comptime T: type) type {
    return struct {
        const Self = @This();

        fn new() Self {
            return .{};
        }

        fn patternAt(self: Self, pattern_point: Tuple(T)) Color(T) {
            _ = self;
            return Color(T).new(pattern_point.x, pattern_point.y, pattern_point.z);
        }
    };
}

test "TestPattern" {
    {
        var shape = Shape(f32).sphere();
        try shape.setTransform(Matrix(f32, 4).identity().scale(2.0, 2.0, 2.0));
        const pattern = Pattern(f32).testPattern();
        const c = pattern.patternAtShape(shape, Tuple(f32).point(2.0, 3.0, 4.0));
        try testing.expect(c.approxEqual(Color(f32).new(1.0, 1.5, 2.0)));
    }

    {
        const shape = Shape(f32).sphere();
        var pattern = Pattern(f32).testPattern();
        try pattern.setTransform(Matrix(f32, 4).identity().scale(2.0, 2.0, 2.0));
        const c = pattern.patternAtShape(shape, Tuple(f32).point(2.0, 3.0, 4.0));
        try testing.expect(c.approxEqual(Color(f32).new(1.0, 1.5, 2.0)));
    }

    {
        var shape = Shape(f32).sphere();
        try shape.setTransform(Matrix(f32, 4).identity().scale(2.0, 2.0, 2.0));
        var pattern = Pattern(f32).testPattern();
        try pattern.setTransform(Matrix(f32, 4).identity().translate(0.5, 1.0, 1.5));
        const c = pattern.patternAtShape(shape, Tuple(f32).point(2.5, 3.0, 3.5));
        try testing.expect(c.approxEqual(Color(f32).new(0.75, 0.5, 0.25)));
    }
}
