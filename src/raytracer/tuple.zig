const std = @import("std");
const testing = std.testing;

/// A 4-component xyzw representation of 3D points and vectors, backed
/// by floats of type `T`.
/// `tuple.w == 0` => `tuple` is a vector.
/// `tuple.w == 1` => `tuple` is a point.
///
/// Vector algebra in this ray tracer follows a left-handed cooridinate
/// system (sorry).
pub fn Tuple(comptime T: type) type {
    return packed struct {
        const Self = @This();
        const tolerance: T = 1e-5;

        x: T,
        y: T,
        z: T,
        w: T,

        /// Creates a `Tuple` from all 4 components. Prefer creation `point` and `vec3`.
        pub inline fn new(x: T, y: T, z: T, w: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = w };
        }

        /// Creates a point.
        pub inline fn point(x: T, y: T, z: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = 1.0 };
        }

        /// Creates a vector.
        pub inline fn vec3(x: T, y: T, z: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = 0.0 };
        }

        /// Creates a `Tuple` from a 4 element array.
        pub inline fn fromBuf(buf: [4]T) Self {
            return .{ .x = buf[0], .y = buf[1], .z = buf[2], .w = buf[3] };
        }

        /// Tests if two tuples should be considered equal.
        pub inline fn approxEqual(self: Self, other: Self) bool {
            return @fabs(self.x - other.x) < tolerance
                and @fabs(self.y - other.y) < tolerance
                and @fabs(self.z - other.z) < tolerance
                and @fabs(self.w - other.w) < tolerance;
        }

        /// Adds `Tuple`s elementwise.
        ///
        /// Assumes either:
        ///     1.) `self` is a vector, and `other` is a vector.
        ///     2.) Exactly one of `self` and `other` is a vector.
        pub inline fn add(self: Self, other: Self) Self {
            return .{ .x = self.x + other.x,
                      .y = self.y + other.y,
                      .z = self.z + other.z,
                      .w = self.w + other.w };
        }

        /// Subtracts `Tuple`s elementwise.
        pub inline fn sub(self: Self, other: Self) Self {
            return .{ .x = self.x - other.x,
                      .y = self.y - other.y,
                      .z = self.z - other.z,
                      .w = self.w - other.w };
        }

        /// Multiplies a `Tuple` by -1.
        ///
        /// Assumes `self` is a vector.
        pub inline fn negate(self: Self) Self {
            return .{ .x = - self.x,
                      .y = - self.y,
                      .z = - self.z,
                      .w = - self.w };
        }

        /// Multiplies a `Tuple` by a `val` elementwise.
        ///
        /// Assumes `self` is a vector.
        pub inline fn mul(self: Self, val: T) Self {
            return .{ .x = self.x * val,
                      .y = self.y * val,
                      .z = self.z * val,
                      .w = self.w * val };
        }

        /// Divides a `Tuple` by a `val` elementwise.
        ///
        /// Assumes `self` is a vector.
        pub inline fn div(self: Self, val: T) Self {
            return .{ .x = self.x / val,
                      .y = self.y / val,
                      .z = self.z / val,
                      .w = self.w / val };
        }

        /// Computes the magninute of a `Tuple`.
        ///
        /// Assumes `self` is a vector.
        pub inline fn magnitude(self: Self) T {
            return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
        }

        /// Normalized a `Tuple`.
        ///
        /// Assumes `self` is a vector.
        pub inline fn normalized(self: Self) Self {
            return self.div(self.magnitude());
        }

        /// Computes the dot product.
        ///
        /// Assumes both `self` and `other` are vectors.
        pub inline fn dot(self: Self, other: Self) T {
            return self.x * other.x + self.y * other.y + self.z * other.z + self.w * other.w;
        }

        /// Computes the (left-handed) cross product.
        ///
        /// Assumes both `self` and `other` are vectors.
        pub inline fn cross(self: Self, other: Self) Self {
            return Self.vec3(
                self.y * other.z - self.z * other.y,
                self.z * other.x - self.x * other.z,
                self.x * other.y - self.y * other.x
            );
        }

        /// Reflects a `Tuple` across `normal`.
        ///
        /// Assumes `self` and `normal` are vectors.
        pub inline fn reflect(self: Self, normal: Self) Self {
            return self.sub(normal.mul(2.0 * self.dot(normal)));
        }

    };
}

test "Tuple ops" {
    // addition
    var a1 = Tuple(f32).point(3.0, -2.0, 5.0);
    var a2 = Tuple(f32).vec3(-2.0, 3.0, 1.0);
    try testing.expect(a1.add(a2).approxEqual(Tuple(f32).point(1.0, 1.0, 6.0)));

    // subtraction
    a1 = Tuple(f32).point(3.0, 2.0, 1.0);
    a2 = Tuple(f32).point(5.0, 6.0, 7.0);
    try testing.expect(a1.sub(a2).approxEqual(Tuple(f32).vec3(-2.0, -4.0, -6.0)));

    a1 = Tuple(f32).point(3.0, 2.0, 1.0);
    a2 = Tuple(f32).vec3(5.0, 6.0, 7.0);
    try testing.expect(a1.sub(a2).approxEqual(Tuple(f32).point(-2.0, -4.0, -6.0)));

    a1 = Tuple(f32).vec3(3.0, 2.0, 1.0);
    a2 = Tuple(f32).vec3(5.0, 6.0, 7.0);
    try testing.expect(a1.sub(a2).approxEqual(Tuple(f32).vec3(-2.0, -4.0, -6.0)));

    // negation
    a1 = Tuple(f32).new(1.0, -2.0, 3.0, -4.0);
    try testing.expect(a1.negate().approxEqual(Tuple(f32).new(-1.0, 2.0, -3.0, 4.0)));

    // scalar multiplication
    a1 = Tuple(f32).new(1.0, -2.0, 3.0, -4.0);
    try testing.expect(a1.mul(3.5).approxEqual(Tuple(f32).new(3.5, -7.0, 10.5, -14.0)));

    // scalar division
    a1 = Tuple(f32).new(1.0, -2.0, 3.0, -4.0);
    try testing.expect(a1.div(2.0).approxEqual(Tuple(f32).new(0.5, -1.0, 1.5, -2.0)));

    // magnitude
    a1 = Tuple(f32).vec3(1.0, 0.0, 0.0);
    try testing.expectApproxEqAbs(a1.magnitude(), 1.0, Tuple(f32).tolerance);

    a1 = Tuple(f32).vec3(1.0, 2.0, 3.0);
    try testing.expectApproxEqAbs(a1.magnitude(), @sqrt(14.0), Tuple(f32).tolerance);

    a1 = Tuple(f32).vec3(-1.0, -2.0, -3.0);
    try testing.expectApproxEqAbs(a1.magnitude(), @sqrt(14.0), Tuple(f32).tolerance);

    // normalization
    a1 = Tuple(f32).vec3(4.0, 0.0, 0.0);
    try testing.expect(a1.normalized().approxEqual(Tuple(f32).vec3(1.0, 0.0, 0.0)));

    a1 = Tuple(f32).vec3(1.0, 2.0, 3.0);
    try testing.expect(a1.normalized().approxEqual(Tuple(f32).vec3(0.26726, 0.53452, 0.80178)));

    a1 = Tuple(f32).vec3(1.0, 2.0, 3.0);
    try testing.expectApproxEqAbs(a1.normalized().magnitude(), 1.0, Tuple(f32).tolerance);

    // dot product
    a1 = Tuple(f32).vec3(1.0, 2.0, 3.0);
    a2 = Tuple(f32).vec3(2.0, 3.0, 4.0);
    try testing.expectApproxEqAbs(a1.dot(a2), 20.0, Tuple(f32).tolerance);

    // cross product
    a1 = Tuple(f32).vec3(1.0, 2.0, 3.0);
    a2 = Tuple(f32).vec3(2.0, 3.0, 4.0);
    try testing.expect(a1.cross(a2).approxEqual(Tuple(f32).vec3(-1.0, 2.0, -1.0)));
    try testing.expect(a2.cross(a1).approxEqual(a1.cross(a2).negate()));

    // reflection
    var v = Tuple(f32).vec3(1.0, -1.0, 0.0);
    var n = Tuple(f32).vec3(0.0, 1.0, 0.0);
    try testing.expect(v.reflect(n).approxEqual(Tuple(f32).vec3(1.0, 1.0, 0.0)));

    v = Tuple(f32).vec3(0.0, -1.0, 0.0);
    n = Tuple(f32).vec3(1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0), 0.0);
    try testing.expect(v.reflect(n).approxEqual(Tuple(f32).vec3(1.0, 0.0, 0.0)));
}
