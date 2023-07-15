const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const inf = std.math.inf;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Ray = @import("../ray.zig").Ray;

const shape = @import("shape.zig");
const Intersection = shape.Intersection;
const Intersections = shape.Intersections;
const sortIntersections = shape.sortIntersections;
const Shape = shape.Shape;

/// A cone object, backed by floats of type `T`.
///
/// All cones are axis-aligned and centered at the origin in their
/// own object space. To move them, rotate them, resize them, etc.
/// in world space, use Shape.setTransform.
pub fn Cone(comptime T: type) type {
    return struct {
        const Self = @This();
        const tolerance: T = 1e-4;

        min: T = -inf(T),
        max: T = inf(T),
        closed: bool = false,

        fn check_cap(ray: Ray(T), t: T, radius: T) bool {
            const x = ray.origin.x + t * ray.direction.x;
            const z = ray.origin.z + t * ray.direction.z;

            return x * x + z * z <= radius * radius;
        }

        fn intersect_caps(cone: *const Shape(T), ray: Ray(T), xs: *Intersections(T)) !void {
            if (!cone.variant.cone.closed or @fabs(ray.direction.y) < Self.tolerance) {
                return;
            }

            var t = (cone.variant.cone.min - ray.origin.y) / ray.direction.y;
            if (check_cap(ray, t, cone.variant.cone.min)) {
                try xs.append(Intersection(T).new(t, cone));
            }

            t = (cone.variant.cone.max - ray.origin.y) / ray.direction.y;
            if (check_cap(ray, t, cone.variant.cone.max)) {
                try xs.append(Intersection(T).new(t, cone));
            }
        }

        pub fn localIntersect(
            self: Self, allocator: Allocator, super: *const Shape(T), ray: Ray(T)
        ) !Intersections(T) {
            const a = ray.direction.x * ray.direction.x
                        - ray.direction.y * ray.direction.y
                        + ray.direction.z * ray.direction.z;

            var xs = Intersections(T).init(allocator);

            const b = 2.0 * ray.origin.x * ray.direction.x
                        - 2.0 * ray.origin.y * ray.direction.y
                        + 2.0 * ray.origin.z * ray.direction.z;

            if (@fabs(a) < Self.tolerance and @fabs(b) < Self.tolerance) {
                // Ray misses
                try Self.intersect_caps(super, ray, &xs);
                return xs;
            }

            const c = ray.origin.x * ray.origin.x
                        - ray.origin.y * ray.origin.y
                        + ray.origin.z * ray.origin.z;

            if (@fabs(a) < Self.tolerance) {
                // This parallel ray intersects once with the surface...
                try xs.append(Intersection(T).new(-c / (2.0 * b), super));

                // ...but might hit a cap on the way out!
                try Self.intersect_caps(super, ray, &xs);
                return xs;
            }

            const discriminant = b * b - 4.0 * a * c;

            if (discriminant < 0.0) {
                // Ray does not intersect
                return xs;
            }

            var t0 = (-b - @sqrt(discriminant)) / (2.0 * a);
            var t1 = (-b + @sqrt(discriminant)) / (2.0 * a);

            if (t0 > t1) {
                const save = t0;
                t0 = t1;
                t1 = save;
            }

            const y0 = ray.origin.y + t0 * ray.direction.y;
            if (self.min < y0 and y0 < self.max) {
                try xs.append(Intersection(T).new(t0, super));
            }

            const y1 = ray.origin.y + t1 * ray.direction.y;
            if (self.min < y1 and y1 < self.max) {
                try xs.append(Intersection(T).new(t1, super));
            }

            try Self.intersect_caps(super, ray, &xs);
            return xs;
        }

        pub fn localNormalAt(self: Self, super: Shape(T), point: Tuple(T)) Tuple(T) {
            _ = super;

            const dist = point.x * point.x + point.z * point.z;

            if (dist < self.max * self.max and point.y >= self.max - Self.tolerance) {
                return Tuple(T).vec3(0.0, 1.0, 0.0);
            } else if (dist < self.min * self.min and point.y <= self.min + Self.tolerance) {
                return Tuple(T).vec3(0.0, -1.0, 0.0);
            } else {
                const y = -std.math.sign(point.y) * @sqrt(point.x * point.x + point.z * point.z);
                return Tuple(T).vec3(point.x, y, point.z);
            }
        }
    };
}

fn testRayIntersectsCone(
    comptime T: type, allocator: Allocator, origin: Tuple(T), direction: Tuple(T), t0: T, t1: T
) !void {
    var cone = Shape(T).cone();
    const r = Ray(T).new(origin, direction.normalized());

    var xs = try cone.intersect(allocator, r);
    defer xs.deinit();

    try testing.expect(xs.items.len == 2);
    try testing.expectApproxEqAbs(xs.items[0].t, t0, Cone(T).tolerance);
    try testing.expectApproxEqAbs(xs.items[1].t, t1, Cone(T).tolerance);
}

test "Intersecting a cone with a ray" {
    const allocator = testing.allocator;

    // Needs f64 precision

    try testRayIntersectsCone(
        f64, allocator, Tuple(f64).point(0.0, 0.0, -5.0), Tuple(f64).vec3(0.0, 0.0, 1.0), 5.0, 5.0
    );

    try testRayIntersectsCone(
        f64, allocator, Tuple(f64).point(0.0, 0.0, -5.0), Tuple(f64).vec3(1.0, 1.0, 1.0), 8.66025, 8.66025
    );

    try testRayIntersectsCone(
        f64, allocator, Tuple(f64).point(1.0, 1.0, -5.0), Tuple(f64).vec3(-0.5, -1.0, 1.0), 4.55006, 49.44994
    );
}

test "Intersecting a cone with a ray parallel to one of its halves" {
    const allocator = testing.allocator;

    var s = Shape(f32).cone();
    const direction = Tuple(f32).vec3(0.0, 1.0, 1.0).normalized();
    const ray = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -1.0), direction);

    const xs = try s.intersect(allocator, ray);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 1);
    try testing.expectApproxEqAbs(xs.items[0].t, 0.35355, Cone(f32).tolerance);
}

fn testRayIntersectsClosedCone(
    comptime T: type, allocator: Allocator, origin: Tuple(T), direction: Tuple(T), count: usize
) !void {
    var cone = Shape(T).cone();

    cone.variant.cone.min = -0.5;
    cone.variant.cone.max = 0.5;
    cone.variant.cone.closed = true;

    const r = Ray(T).new(origin, direction.normalized());

    const xs = try cone.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, count);
}

test "Intersecting a cone's end caps" {
    const allocator = testing.allocator;

    try testRayIntersectsClosedCone(
        f32, allocator, Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 1.0, 0.0), 0
    );

    try testRayIntersectsClosedCone(
        f32, allocator, Tuple(f32).point(0.0, 0.0, -0.25), Tuple(f32).vec3(0.0, 1.0, 1.0), 2
    );

    try testRayIntersectsClosedCone(
        f32, allocator, Tuple(f32).point(0.0, 0.0, -0.25), Tuple(f32).vec3(0.0, 1.0, 0.0), 4
    );
}


fn testNormalOnCone(comptime T: type, point: Tuple(T), normal: Tuple(T)) !void {
    var cone = Shape(T).cone();

    try testing.expect(cone.normalAt(point).approxEqual(normal));
}

test "Computing the normal vector on a cone" {
    try testNormalOnCone(
        f32, Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 0.0)
    );

    try testNormalOnCone(
        f32, Tuple(f32).point(1.0, 1.0, 1.0), Tuple(f32).vec3(1.0, -@sqrt(2.0), 1.0).normalized()
    );

    try testNormalOnCone(
        f32, Tuple(f32).point(-1.0, -1.0, 0.0), Tuple(f32).vec3(-1.0, 1.0, 0.0).normalized()
    );
}
