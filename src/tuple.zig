const std = @import("std");
const testing = std.testing;

const tolerance = @import("definitions.zig").tolerance;
const F = @import("definitions.zig").F;

const Tuple = struct {
    v: @Vector(4, F),

    pub fn new(x: F, y: F, z: F, w: F) Tuple {
        return Tuple{ .v = @Vector(4, F){ x, y, z, w } };
    }

    pub fn new_point(x: F, y: F, z: F) Tuple {
        return Tuple{ .v = @Vector(4, F){ x, y, z, 1.0 } };
    }

    pub fn new_vec3(x: F, y: F, z: F) Tuple {
        return Tuple{ .v = @Vector(4, F){ x, y, z, 0.0 } };
    }

    pub fn approx_equal(self: Tuple, other: Tuple) bool {
        return @reduce(.And, @fabs(self.v - other.v) < @splat(4, tolerance));
    }

    pub fn add(self: Tuple, other: Tuple) Tuple {
        return Tuple{ .v = self.v + other.v };
    }

    pub fn sub(self: Tuple, other: Tuple) Tuple {
        return Tuple{ .v = self.v - other.v };
    }

    pub fn negate(self: Tuple) Tuple {
        return Tuple{ .v = self.v * @splat(4, @as(F, -1.0)) };
    }

    pub fn mul(self: Tuple, val: F) Tuple {
        return Tuple{ .v = self.v * @splat(4, val) };
    }

    pub fn div(self: Tuple, val: F) Tuple {
        return Tuple{ .v = self.v / @splat(4, val) };
    }

    pub fn magnitude(self: Tuple) F {
        return @sqrt(@reduce(.Add, self.v * self.v));
    }

    pub fn normalized(self: Tuple) Tuple {
        return self.div(self.magnitude());
    }

    pub fn dot(self: Tuple, other: Tuple) F {
        return @reduce(.Add, self.v * other.v);
    }

    pub fn cross(self: Tuple, other: Tuple) Tuple {
        return Tuple.new_vec3(
            self.v[1] * other.v[2] - self.v[2] * other.v[1],
            self.v[2] * other.v[0] - self.v[0] * other.v[2],
            self.v[0] * other.v[1] - self.v[1] * other.v[0]
        );
    }
};

test "tuple ops" {
    // addition
    var a1 = Tuple.new_point(3.0, -2.0, 5.0);
    var a2 = Tuple.new_vec3(-2.0, 3.0, 1.0);
    try testing.expect(a1.add(a2).approx_equal(Tuple.new_point(1, 1, 6)));

    // subtraction
    a1 = Tuple.new_point(3.0, 2.0, 1.0);
    a2 = Tuple.new_point(5.0, 6.0, 7.0);
    try testing.expect(a1.sub(a2).approx_equal(Tuple.new_vec3(-2.0, -4.0, -6.0)));

    a1 = Tuple.new_point(3.0, 2.0, 1.0);
    a2 = Tuple.new_vec3(5.0, 6.0, 7.0);
    try testing.expect(a1.sub(a2).approx_equal(Tuple.new_point(-2.0, -4.0, -6.0)));

    a1 = Tuple.new_vec3(3.0, 2.0, 1.0);
    a2 = Tuple.new_vec3(5.0, 6.0, 7.0);
    try testing.expect(a1.sub(a2).approx_equal(Tuple.new_vec3(-2.0, -4.0, -6.0)));

    // negation
    a1 = Tuple.new(1.0, -2.0, 3.0, -4.0);
    try testing.expect(a1.negate().approx_equal(Tuple.new(-1.0, 2.0, -3.0, 4.0)));

    // scalar multiplication
    a1 = Tuple.new(1.0, -2.0, 3.0, -4.0);
    try testing.expect(a1.mul(3.5).approx_equal(Tuple.new(3.5, -7.0, 10.5, -14.0)));

    // scalar division
    a1 = Tuple.new(1.0, -2.0, 3.0, -4.0);
    try testing.expect(a1.div(2.0).approx_equal(Tuple.new(0.5, -1.0, 1.5, -2.0)));

    // magnitude
    a1 = Tuple.new_vec3(1.0, 0.0, 0.0);
    try testing.expectApproxEqAbs(a1.magnitude(), 1.0, tolerance);

    a1 = Tuple.new_vec3(1.0, 2.0, 3.0);
    try testing.expectApproxEqAbs(a1.magnitude(), @sqrt(14.0), tolerance);

    a1 = Tuple.new_vec3(-1.0, -2.0, -3.0);
    try testing.expectApproxEqAbs(a1.magnitude(), @sqrt(14.0), tolerance);

    // normalization
    a1 = Tuple.new_vec3(4.0, 0.0, 0.0);
    try testing.expect(a1.normalized().approx_equal(Tuple.new_vec3(1.0, 0.0, 0.0)));

    a1 = Tuple.new_vec3(1.0, 2.0, 3.0);
    try testing.expect(a1.normalized().approx_equal(Tuple.new_vec3(0.26726, 0.53452, 0.80178)));

    a1 = Tuple.new_vec3(1.0, 2.0, 3.0);
    try testing.expectApproxEqAbs(a1.normalized().magnitude(), 1.0, tolerance);

    // dot product
    a1 = Tuple.new_vec3(1.0, 2.0, 3.0);
    a2 = Tuple.new_vec3(2.0, 3.0, 4.0);
    try testing.expectApproxEqAbs(a1.dot(a2), 20.0, tolerance);

    // cross product
    a1 = Tuple.new_vec3(1.0, 2.0, 3.0);
    a2 = Tuple.new_vec3(2.0, 3.0, 4.0);
    try testing.expect(a1.cross(a2).approx_equal(Tuple.new_vec3(-1.0, 2.0, -1.0)));
    try testing.expect(a2.cross(a1).approx_equal(a1.cross(a2).negate()));
}
