const std = @import("std");
const testing = std.testing;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Color = @import("../color.zig").Color;
const Shape = @import("../shapes/shape.zig").Shape;
const Solid = @import("solid.zig").Solid;
const Blend = @import("blend.zig").Blend;
const Perturb = @import("perturb.zig").Perturb;
const Stripes = @import("stripes.zig").Stripes;
const Gradient = @import("gradient.zig").Gradient;
const RadialGradient = @import("gradient.zig").RadialGradient;
const Rings = @import("rings.zig").Rings;
const Checkers = @import("checkers.zig").Checkers;

/// A pattern to be put on a `Material`, backed by floats of type `T`.
pub fn Pattern(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The various concrete patterns. Structs that can be placed in
        /// this tagged union must provide the following function:
        ///
        /// fn patternAt(self: Self, pattern_point: Tuple(T), object_point: Tuple(T)) Color(T);
        ///
        /// `patternAt` is responsible for returning the pattern's color at
        /// the point `pattern_point` in pattern space. `object_point` may be
        /// used for higher-order patterns.
        const Variant = union(enum) {
            test_pattern: TestPattern(T),
            solid: Solid(T),
            blend: Blend(T),
            perturb: Perturb(T),
            stripes: Stripes(T),
            gradient: Gradient(T),
            radial_gradient: RadialGradient(T),
            rings: Rings(T),
            checkers: Checkers(T),
        };

        _transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        _inverse_transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        variant: Variant,

        /// Creates a new pattern.
        fn new(variant: Variant) Self {
            return .{ .variant = variant };
        }

        /// Creates a new test pattern.
        pub fn testPattern() Self {
            return Self.new(Self.Variant { .test_pattern = TestPattern(T).new() });
        }

        /// Creates a new pattern of just one color.
        pub fn solid(a: Color(T)) Self {
            return Self.new(Self.Variant { .solid = Solid(T).new(a) });
        }

        /// Creates a new pattern that blends two other patterns.
        pub fn blend(a: *const Self, b: *const Self) Self {
            return Self.new(Self.Variant { .blend = Blend(T).new(a, b) });
        }

        /// Creates a new pattern that perturb's a pattern.
        pub fn perturb(a: *const Self, info: Perturb(T).PerturbInfo) Self {
            return Self.new(Self.Variant { .perturb = Perturb(T).new(a, info) });
        }

        /// Creates a new pattern of stripes.
        pub fn stripes(a: *const Self, b: *const Self) Self {
            return Self.new(Self.Variant { .stripes = Stripes(T).new(a, b) });
        }

        /// Creates a new gradient pattern.
        pub fn gradient(a: *const Self, b: *const Self) Self {
            return Self.new(Self.Variant { .gradient = Gradient(T).new(a, b) });
        }

        pub fn radialGradient(a: *const Self, b: *const Self) Self {
            return Self.new(Self.Variant { .radial_gradient = RadialGradient(T).new(a, b) });
        }

        /// Creates a new pattern of rings.
        pub fn rings(a: *const Self, b: *const Self) Self {
            return Self.new(Self.Variant { .rings = Rings(T).new(a, b) });
        }

        /// Creates a new checkered pattern.
        pub fn checkers(a: *const Self, b: *const Self) Self {
            return Self.new(Self.Variant { .checkers = Checkers(T).new(a, b) });
        }

        /// Transforms a pattern relative to shape on which it lies.
        pub fn setTransform(self: *Self, matrix: Matrix(T, 4)) !void {
            self._transform = matrix;
            self._inverse_transform = try matrix.inverse();
        }

        /// Determines the pattern's color at the point `object_point` in object space.
        ///
        /// Assumes `object_point` is a point.
        pub fn patternAt(self: Self, object_point: Tuple(T)) Color(T) {
            const pattern_point = self._inverse_transform.tupleMul(object_point);

            const Tag = @typeInfo(@TypeOf(self.variant)).Union.tag_type.?;
            inline for (@typeInfo(Tag).Enum.fields) |field| {
                if (field.value == @intFromEnum(self.variant)) {
                    return @field(self.variant, field.name).patternAt(pattern_point, object_point);
                }
            }

            unreachable;
        }

        /// Determines the pattern's color at the point `world_point` in world space.
        ///
        /// Assumes `world_point` is a point.
        pub fn patternAtShape(self: Self, shape: Shape(T), world_point: Tuple(T)) Color(T) {
            const object_point = shape._inverse_transform.tupleMul(world_point);
            return self.patternAt(object_point);
        }
    };
}

/// A simple pattern for testing.
fn TestPattern(comptime T: type) type {
    return struct {
        const Self = @This();

        fn new() Self {
            return .{};
        }

        fn patternAt(self: Self, pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
            _ = self;
            _ = object_point;
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
