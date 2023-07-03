const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Ray = @import("../ray.zig").Ray;

const shape = @import("shape.zig");
const Intersection = shape.Intersection;
const Intersections = shape.Intersections;
const sortIntersections = shape.sortIntersections;
const Shape = shape.Shape;

/// A cube object, backed by floats of type `T`.
///
/// All cubes are axis-aligned and centered at the origin in their
/// own object space. To move them, rotate them, resize them, etc.
/// in world space, use Shape.setTransform.
pub fn Cube(comptime T: type) type {
    return struct {
        const Self = @This();

        fn checkAxis(origin: T, direction: T) [2]T {
            const epsilon = 1e-5;

            const tmin_numerator = -1.0 - origin;
            const tmax_numerator = 1.0 - origin;

            var tmin: T = 0.0;
            var tmax: T = 0.0;

            if (@fabs(direction) >= epsilon) {
                tmin = tmin_numerator / direction;
                tmax = tmax_numerator / direction;
            } else {
                tmin = tmin_numerator * std.math.inf(T);
                tmax = tmax_numerator * std.math.inf(T);
            }

            if (tmin > tmax) {
                const save = tmax;
                tmax = tmin;
                tmin = save;
            }

            return [_]T {tmin, tmax};
        }

        pub fn localIntersect(self: Self, allocator: Allocator, super: Shape(T), ray: Ray(T)) !Intersections(T) {
            _ = self;

            const xt = Self.checkAxis(ray.origin.x, ray.direction.x);
            const xtmin = xt[0];
            const xtmax = xt[1];

            const yt = Self.checkAxis(ray.origin.y, ray.direction.y);
            const ytmin = yt[0];
            const ytmax = yt[1];

            const zt = Self.checkAxis(ray.origin.z, ray.direction.z);
            const ztmin = zt[0];
            const ztmax = zt[1];

            const tmin = @max(xtmin, @max(ytmin, ztmin));
            const tmax = @min(xtmax, @min(ytmax, ztmax));

            var xs = Intersections(T).init(allocator);
            if (tmin > tmax) {
                return xs;
            }

            try xs.append(Intersection(T).new(tmin, super));
            try xs.append(Intersection(T).new(tmax, super));

            return xs;
        }

        pub fn localNormalAt(self: Self, super: Shape(T), point: Tuple(T)) Tuple(T) {
            _ = self;
            _ = super;

            const abs_x = @fabs(point.x);
            const abs_y = @fabs(point.y);
            const abs_z = @fabs(point.z);
            const maxc = @max(abs_x, @max(abs_y, abs_z));

            if (maxc == abs_x) {
                return Tuple(T).vec3(point.x, 0.0, 0.0);
            } else if (maxc == abs_y) {
                return Tuple(T).vec3(0.0, point.y, 0.0);
            } else {
                return Tuple(T).vec3(0.0, 0.0, point.z);
            }
        }
    };
}

fn testRayIntersectsCube(
    comptime T: type, allocator: Allocator, origin: Tuple(T), direction: Tuple(T), t1: T, t2: T
) !void {
    const tolerance = 1e-5;
    var c = Shape(f32).cube();
    const r = Ray(T).new(origin, direction);

    var xs = try c.intersect(allocator, r);
    defer xs.deinit();

    try testing.expect(xs.items.len == 2);
    try testing.expectApproxEqAbs(xs.items[0].t, t1, tolerance);
    try testing.expectApproxEqAbs(xs.items[1].t, t2, tolerance);
}

test "A ray intersects a cube" {
    const allocator = testing.allocator;

    try testRayIntersectsCube(
        f32, allocator, Tuple(f32).point(5.0, 0.5, 0.0), Tuple(f32).vec3(-1.0, 0.0, 0.0), 4.0, 6.0
    );

    try testRayIntersectsCube(
        f32, allocator, Tuple(f32).point(-5.0, 0.5, 0.0), Tuple(f32).vec3(1.0, 0.0, 0.0), 4.0, 6.0
    );

    try testRayIntersectsCube(
        f32, allocator, Tuple(f32).point(0.5, 5.0, 0.0), Tuple(f32).vec3(0.0, -1.0, 0.0), 4.0, 6.0
    );

    try testRayIntersectsCube(
        f32, allocator, Tuple(f32).point(0.5, -5.0, 0.0), Tuple(f32).vec3(0.0, 1.0, 0.0), 4.0, 6.0
    );

    try testRayIntersectsCube(
        f32, allocator, Tuple(f32).point(0.5, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0), 4.0, 6.0
    );

    try testRayIntersectsCube(
        f32, allocator, Tuple(f32).point(0.0, 0.5, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0), -1.0, 1.0
    );
}

fn testRayMissesCube(
    comptime T: type, allocator: Allocator, origin: Tuple(T), direction: Tuple(T)
) !void {
    var c = Shape(f32).cube();
    const r = Ray(T).new(origin, direction);

    var xs = try c.intersect(allocator, r);
    defer xs.deinit();

    try testing.expect(xs.items.len == 0);
}

test "A ray misses a cube" {
    const allocator = testing.allocator;

    try testRayMissesCube(
        f32, allocator, Tuple(f32).point(-2.0, 0.0, 0.0), Tuple(f32).vec3(0.2673, 0.5345, 0.8018)
    );

    try testRayMissesCube(
        f32, allocator, Tuple(f32).point(0.0, -2.0, 0.0), Tuple(f32).vec3(0.8018, 0.2673, 0.5345)
    );

    try testRayMissesCube(
        f32, allocator, Tuple(f32).point(0.0, 0.0, -2.0), Tuple(f32).vec3(0.5345, 0.8018, 0.2673)
    );

    try testRayMissesCube(
        f32, allocator, Tuple(f32).point(2.0, 0.0, 2.0), Tuple(f32).vec3(0.0, 0.0, -1.0)
    );

    try testRayMissesCube(
        f32, allocator, Tuple(f32).point(0.0, 2.0, 2.0), Tuple(f32).vec3(0.0, -1.0, 0.0)
    );

    try testRayMissesCube(
        f32, allocator, Tuple(f32).point(2.0, 2.0, 0.0), Tuple(f32).vec3(-1.0, 0.0, 0.0)
    );
}

fn testNormalOnCube(comptime T: type, point: Tuple(f32), normal: Tuple(f32)) !void {
    const c = Shape(T).cube();

    try testing.expect(c.normalAt(point).approxEqual(normal));
}

test "The normal on a cube" {
    try testNormalOnCube(f32, Tuple(f32).point(1, 0.5, -0.8), Tuple(f32).vec3(1.0, 0.0, 0.0));
    try testNormalOnCube(f32, Tuple(f32).point(-1, -0.2, 0.9), Tuple(f32).vec3(-1.0, 0.0, 0.0));
    try testNormalOnCube(f32, Tuple(f32).point(-0.4, 1, -0.1), Tuple(f32).vec3(0.0, 1.0, 0.0));
    try testNormalOnCube(f32, Tuple(f32).point(0.3, -1, -0.7), Tuple(f32).vec3(0.0, -1.0, 0.0));
    try testNormalOnCube(f32, Tuple(f32).point(-0.6, 0.3, 1), Tuple(f32).vec3(0.0, 0.0, 1.0));
    try testNormalOnCube(f32, Tuple(f32).point(0.4, 0.4, -1), Tuple(f32).vec3(0.0, 0.0, -1.0));
    try testNormalOnCube(f32, Tuple(f32).point(1.0, 1.0, 1.0), Tuple(f32).vec3(1.0, 0.0, 0.0));
    try testNormalOnCube(f32, Tuple(f32).point(-1.0, -1.0, -1.0), Tuple(f32).vec3(-1.0, 0.0, 0.0));
}
