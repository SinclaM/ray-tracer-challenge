const std = @import("std");
const testing = std.testing;

const Tuple = @import("tuple.zig").Tuple;
const Matrix = @import("matrix.zig").Matrix;

/// A ray with an origin and direction, backed by
/// floats of type `T`.
pub fn Ray(comptime T: type) type {
    return struct {
        const Self = @This();

        origin: Tuple(T),
        direction: Tuple(T),

        /// Creates a new `Ray`.
        ///
        /// Assumes `origin` is a point, and `direction` is a vector.
        pub fn new(origin: Tuple(T), direction: Tuple(T)) Self {
            return .{ .origin = origin, .direction = direction };
        }

        /// Computes the point at `t` units along the `self.direction`,
        /// starting at `self.origin`.
        pub fn position(self: Self, t: T) Tuple(T) {
            return self.origin.add(self.direction.mul(t));
        }

        /// Transforms a ray under a matrix.
        pub fn transform(self: Self, matrix: Matrix(T, 4)) Self {
            return Self.new(matrix.tupleMul(self.origin), matrix.tupleMul(self.direction));
        }

    };
}

test "Ray creation" {
    const r = Ray(f32).new(Tuple(f32).point(1.0, 2.0, 3.0), Tuple(f32).vec3(4.0, 5.0, 6.0));
    try testing.expectEqual(r.origin, Tuple(f32).point(1.0, 2.0, 3.0));
    try testing.expectEqual(r.direction, Tuple(f32).vec3(4.0, 5.0, 6.0));
}

test "Position" {
    const r = Ray(f32).new(Tuple(f32).point(2.0, 3.0, 4.0), Tuple(f32).vec3(1.0, 0.0, 0.0));
    try testing.expectEqual(r.position(0.0), r.origin);
    try testing.expect(r.position(1.0).approxEqual(Tuple(f32).point(3.0, 3.0, 4.0)));
    try testing.expect(r.position(-1.0).approxEqual(Tuple(f32).point(1.0, 3.0, 4.0)));
    try testing.expect(r.position(2.5).approxEqual(Tuple(f32).point(4.5, 3.0, 4.0)));
}

test "Transforming" {
    var r = Ray(f32).new(Tuple(f32).point(1.0, 2.0, 3.0), Tuple(f32).vec3(0.0, 1.0, 0.0));
    var m = Matrix(f32, 4).identity().translate(3.0, 4.0, 5.0);
    var r2 = r.transform(m);

    try testing.expect(r2.origin.approxEqual(Tuple(f32).point(4.0, 6.0, 8.0)));
    try testing.expect(r2.direction.approxEqual(r.direction));

    m = Matrix(f32, 4).identity().scale(2.0, 3.0, 4.0);
    r2 = r.transform(m);

    try testing.expect(r2.origin.approxEqual(Tuple(f32).point(2.0, 6.0, 12.0)));
    try testing.expect(r2.direction.approxEqual(Tuple(f32).vec3(0.0, 3.0, 0.0)));
}
