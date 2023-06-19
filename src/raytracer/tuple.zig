const std = @import("std");
const testing = std.testing;


pub fn Tuple(comptime T: type) type {
    return packed struct {
        const Self = @This();
        const tolerance: T = 1e-5;

        x: T,
        y: T,
        z: T,
        w: T,

        pub inline fn new(x: T, y: T, z: T, w: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = w };
        }

        pub inline fn new_point(x: T, y: T, z: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = 1.0 };
        }

        pub inline fn new_vec3(x: T, y: T, z: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = 0.0 };
        }

        pub inline fn approx_equal(self: Self, other: Self) bool {
            return @fabs(self.x - other.x) < tolerance
                and @fabs(self.y - other.y) < tolerance
                and @fabs(self.z - other.z) < tolerance
                and @fabs(self.w - other.w) < tolerance;
        }

        pub inline fn add(self: Self, other: Self) Self {
            return .{ .x = self.x + other.x,
                      .y = self.y + other.y,
                      .z = self.z + other.z,
                      .w = self.w + other.w };
        }

        pub inline fn sub(self: Self, other: Self) Self {
            return .{ .x = self.x - other.x,
                      .y = self.y - other.y,
                      .z = self.z - other.z,
                      .w = self.w - other.w };
        }

        pub inline fn negate(self: Self) Self {
            return .{ .x = - self.x,
                      .y = - self.y,
                      .z = - self.z,
                      .w = - self.w };
        }

        pub inline fn mul(self: Self, val: T) Self {
            return .{ .x = self.x * val,
                      .y = self.y * val,
                      .z = self.z * val,
                      .w = self.w * val };
        }

        pub inline fn div(self: Self, val: T) Self {
            return .{ .x = self.x / val,
                      .y = self.y / val,
                      .z = self.z / val,
                      .w = self.w / val };
        }

        pub inline fn magnitude(self: Self) T {
            return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
        }

        pub inline fn normalized(self: Self) Self {
            return self.div(self.magnitude());
        }

        pub inline fn dot(self: Self, other: Self) T {
            return self.x * other.x + self.y * other.y + self.z * other.z + self.w * other.w;
        }

        pub inline fn cross(self: Self, other: Self) Self {
            return Self.new_vec3(
                self.y * other.z - self.z * other.y,
                self.z * other.x - self.x * other.z,
                self.x * other.y - self.y * other.x
            );
        }

    };
}

test "Tuple ops" {
    // addition
    var a1 = Tuple(f32).new_point(3.0, -2.0, 5.0);
    var a2 = Tuple(f32).new_vec3(-2.0, 3.0, 1.0);
    try testing.expect(a1.add(a2).approx_equal(Tuple(f32).new_point(1.0, 1.0, 6.0)));

    // subtraction
    a1 = Tuple(f32).new_point(3.0, 2.0, 1.0);
    a2 = Tuple(f32).new_point(5.0, 6.0, 7.0);
    try testing.expect(a1.sub(a2).approx_equal(Tuple(f32).new_vec3(-2.0, -4.0, -6.0)));

    a1 = Tuple(f32).new_point(3.0, 2.0, 1.0);
    a2 = Tuple(f32).new_vec3(5.0, 6.0, 7.0);
    try testing.expect(a1.sub(a2).approx_equal(Tuple(f32).new_point(-2.0, -4.0, -6.0)));

    a1 = Tuple(f32).new_vec3(3.0, 2.0, 1.0);
    a2 = Tuple(f32).new_vec3(5.0, 6.0, 7.0);
    try testing.expect(a1.sub(a2).approx_equal(Tuple(f32).new_vec3(-2.0, -4.0, -6.0)));

    // negation
    a1 = Tuple(f32).new(1.0, -2.0, 3.0, -4.0);
    try testing.expect(a1.negate().approx_equal(Tuple(f32).new(-1.0, 2.0, -3.0, 4.0)));

    // scalar multiplication
    a1 = Tuple(f32).new(1.0, -2.0, 3.0, -4.0);
    try testing.expect(a1.mul(3.5).approx_equal(Tuple(f32).new(3.5, -7.0, 10.5, -14.0)));

    // scalar division
    a1 = Tuple(f32).new(1.0, -2.0, 3.0, -4.0);
    try testing.expect(a1.div(2.0).approx_equal(Tuple(f32).new(0.5, -1.0, 1.5, -2.0)));

    // magnitude
    a1 = Tuple(f32).new_vec3(1.0, 0.0, 0.0);
    try testing.expectApproxEqAbs(a1.magnitude(), 1.0, Tuple(f32).tolerance);

    a1 = Tuple(f32).new_vec3(1.0, 2.0, 3.0);
    try testing.expectApproxEqAbs(a1.magnitude(), @sqrt(14.0), Tuple(f32).tolerance);

    a1 = Tuple(f32).new_vec3(-1.0, -2.0, -3.0);
    try testing.expectApproxEqAbs(a1.magnitude(), @sqrt(14.0), Tuple(f32).tolerance);

    // normalization
    a1 = Tuple(f32).new_vec3(4.0, 0.0, 0.0);
    try testing.expect(a1.normalized().approx_equal(Tuple(f32).new_vec3(1.0, 0.0, 0.0)));

    a1 = Tuple(f32).new_vec3(1.0, 2.0, 3.0);
    try testing.expect(a1.normalized().approx_equal(Tuple(f32).new_vec3(0.26726, 0.53452, 0.80178)));

    a1 = Tuple(f32).new_vec3(1.0, 2.0, 3.0);
    try testing.expectApproxEqAbs(a1.normalized().magnitude(), 1.0, Tuple(f32).tolerance);

    // dot product
    a1 = Tuple(f32).new_vec3(1.0, 2.0, 3.0);
    a2 = Tuple(f32).new_vec3(2.0, 3.0, 4.0);
    try testing.expectApproxEqAbs(a1.dot(a2), 20.0, Tuple(f32).tolerance);

    // cross product
    a1 = Tuple(f32).new_vec3(1.0, 2.0, 3.0);
    a2 = Tuple(f32).new_vec3(2.0, 3.0, 4.0);
    try testing.expect(a1.cross(a2).approx_equal(Tuple(f32).new_vec3(-1.0, 2.0, -1.0)));
    try testing.expect(a2.cross(a1).approx_equal(a1.cross(a2).negate()));
}
