const std = @import("std");
const testing = std.testing;

const Tuple = @import("tuple.zig").Tuple;

pub fn Ray(comptime T: type) type {
    return struct {
        const Self = @This();

        origin: Tuple(T),
        direction: Tuple(T),

        pub fn new(origin: Tuple(T), direction: Tuple(T)) Self {
            return .{ .origin = origin, .direction = direction };
        }

        pub fn position(self: Self, t: T) Tuple(T) {
            return self.origin.add(self.direction.mul(t));
        }
    };
}

test "Ray creation" {
    const r = Ray(f32).new(Tuple(f32).new_point(1.0, 2.0, 3.0), Tuple(f32).new_vec3(4.0, 5.0, 6.0));
    try testing.expectEqual(r.origin, Tuple(f32).new_point(1.0, 2.0, 3.0));
    try testing.expectEqual(r.direction, Tuple(f32).new_vec3(4.0, 5.0, 6.0));
}

test "Position" {
    const r = Ray(f32).new(Tuple(f32).new_point(2.0, 3.0, 4.0), Tuple(f32).new_vec3(1.0, 0.0, 0.0));
    try testing.expectEqual(r.position(0.0), r.origin);
    try testing.expect(r.position(1.0).approx_equal(Tuple(f32).new_point(3.0, 3.0, 4.0)));
    try testing.expect(r.position(-1.0).approx_equal(Tuple(f32).new_point(1.0, 3.0, 4.0)));
    try testing.expect(r.position(2.5).approx_equal(Tuple(f32).new_point(4.5, 3.0, 4.0)));
}
