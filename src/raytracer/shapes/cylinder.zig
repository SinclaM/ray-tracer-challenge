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

/// A cylinder object, backed by floats of type `T`.
///
/// All cylinders are axis-aligned and centered at the origin in their
/// own object space. To move them, rotate them, resize them, etc.
/// in world space, use Shape.setTransform.
pub fn Cylinder(comptime T: type) type {
    return struct {
        const Self = @This();
        const tolerance: T = 1e-5;

        min: T = -inf(T),
        max: T = inf(T),
        closed: bool = false,

        fn check_cap(ray: Ray(T), t: T) bool {
            const x = ray.origin.x + t * ray.direction.x;
            const z = ray.origin.z + t * ray.direction.z;

            return x * x + z * z <= 1.0;
        }

        fn intersect_caps(cyl: *const Shape(T), ray: Ray(T), xs: *Intersections(T)) !void {
            if (!cyl.variant.cylinder.closed or @abs(ray.direction.y) < Self.tolerance) {
                return;
            }

            var t = (cyl.variant.cylinder.min - ray.origin.y) / ray.direction.y;
            if (check_cap(ray, t)) {
                try xs.append(Intersection(T).new(t, cyl));
            }

            t = (cyl.variant.cylinder.max - ray.origin.y) / ray.direction.y;
            if (check_cap(ray, t)) {
                try xs.append(Intersection(T).new(t, cyl));
            }
        }

        pub fn localIntersect(
            self: Self, allocator: Allocator, super: *const Shape(T), ray: Ray(T)
        ) !Intersections(T) {
            const a = ray.direction.x * ray.direction.x + ray.direction.z * ray.direction.z;

            var xs = Intersections(T).init(allocator);

            if (@abs(a) < Self.tolerance) {
                // Ray is parallel to y-axis
                try Self.intersect_caps(super, ray, &xs);
                return xs;
            }

            const b = 2.0 * ray.origin.x * ray.direction.x + 2.0 * ray.origin.z * ray.direction.z;
            const c = ray.origin.x * ray.origin.x + ray.origin.z * ray.origin.z - 1.0;

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

        pub fn localNormalAt(self: Self, point: Tuple(T), hit: Intersection(T)) Tuple(T) {
            _ = hit;

            const dist = point.x * point.x + point.z * point.z;

            if (dist < 1.0 and point.y >= self.max - Self.tolerance) {
                return Tuple(T).vec3(0.0, 1.0, 0.0);
            } else if (dist < 1.0 and point.y <= self.min + Self.tolerance) {
                return Tuple(T).vec3(0.0, -1.0, 0.0);
            } else {
                return Tuple(T).vec3(point.x, 0.0, point.z);
            }
        }

        pub fn bounds(self: Self) Shape(T) {
            var box = Shape(T).boundingBox();
            box.variant.bounding_box.min = Tuple(T).point(-1.0, self.min, -1.0);
            box.variant.bounding_box.max = Tuple(T).point(1.0, self.max, 1.0);

            return box;
        }
    };
}

fn testRayMissesCylinder(
    comptime T: type, allocator: Allocator, origin: Tuple(T), direction: Tuple(T)
) !void {
    var cyl = Shape(T).cylinder();
    const r = Ray(T).new(origin, direction.normalized());
    
    const xs = try cyl.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 0);
}

test "A ray misses a cylinder" {
    const allocator = testing.allocator;

    try testRayMissesCylinder(
        f32, allocator, Tuple(f32).point(1.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 1.0, 0.0)
    );

    try testRayMissesCylinder(
        f32, allocator, Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 1.0, 0.0)
    );

    try testRayMissesCylinder(
        f32, allocator, Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(1.0, 1.0, 1.0)
    );
}

fn testRayIntersectsCylinder(
    comptime T: type, allocator: Allocator, origin: Tuple(T), direction: Tuple(T), t0: T, t1: T
) !void {
    var cyl = Shape(T).cylinder();
    const r = Ray(T).new(origin, direction.normalized());

    var xs = try cyl.intersect(allocator, r);
    defer xs.deinit();

    try testing.expect(xs.items.len == 2);
    try testing.expectApproxEqAbs(xs.items[0].t, t0, Cylinder(T).tolerance);
    try testing.expectApproxEqAbs(xs.items[1].t, t1, Cylinder(T).tolerance);
}

test "A ray strikes a cylinder" {
    const allocator = testing.allocator;

    try testRayIntersectsCylinder(
        f32, allocator, Tuple(f32).point(1.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0), 5.0, 5.0
    );

    try testRayIntersectsCylinder(
        f32, allocator, Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0), 4.0, 6.0
    );

    try testRayIntersectsCylinder(
        f32, allocator, Tuple(f32).point(0.5, 0.0, -5.0), Tuple(f32).vec3(0.1, 1.0, 1.0), 6.80800, 7.08869
    );
}

fn testNormalOnCylinder(comptime T: type, point: Tuple(f32), normal: Tuple(f32)) !void {
    var cyl = Shape(T).cylinder();
    try testing.expect(cyl.normalAt(point, undefined).approxEqual(normal));
}

test "Normal vector on a cylinder" {
    try testNormalOnCylinder(
        f32, Tuple(f32).point(1.0, 0.0, 0.0), Tuple(f32).vec3(1.0, 0.0, 0.0)
    );

    try testNormalOnCylinder(
        f32, Tuple(f32).point(0.0, 5.0, -1.0), Tuple(f32).vec3(0.0, 0.0, -1.0)
    );

    try testNormalOnCylinder(
        f32, Tuple(f32).point(0.0, -2.0, 1.0), Tuple(f32).vec3(0.0, 0.0, 1.0)
    );

    try testNormalOnCylinder(
        f32, Tuple(f32).point(-1.0, 1.0, 0.0), Tuple(f32).vec3(-1.0, 0.0, 0.0)
    );
}

test "The default minimum and maximum value for a cylinder" {
    const cyl = Cylinder(f32) {};

    try testing.expectEqual(cyl.min, -inf(f32));
    try testing.expectEqual(cyl.max, inf(f32));
}

fn testRayIntersectsTruncatedCylinder(
    comptime T: type, allocator: Allocator, origin: Tuple(T), direction: Tuple(T), count: usize
) !void {
    var cyl = Shape(T).cylinder();

    cyl.variant.cylinder.min = 1.0;
    cyl.variant.cylinder.max = 2.0;

    const r = Ray(T).new(origin, direction.normalized());

    const xs = try cyl.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, count);
}

test "Intersecting a constrained cylinder" {
    const allocator = testing.allocator;

    try testRayIntersectsTruncatedCylinder(
        f32, allocator, Tuple(f32).point(0.0, 1.5, 0.0), Tuple(f32).vec3(0.1, 1.0, 0.0), 0
    );

    try testRayIntersectsTruncatedCylinder(
        f32, allocator, Tuple(f32).point(0.0, 3.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0), 0
    );

    try testRayIntersectsTruncatedCylinder(
        f32, allocator, Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0), 0
    );

    try testRayIntersectsTruncatedCylinder(
        f32, allocator, Tuple(f32).point(0.0, 2.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0), 0
    );

    try testRayIntersectsTruncatedCylinder(
        f32, allocator, Tuple(f32).point(0.0, 1.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0), 0
    );

    try testRayIntersectsTruncatedCylinder(
        f32, allocator, Tuple(f32).point(0.0, 1.5, -2.0), Tuple(f32).vec3(0.0, 0.0, 1.0), 2
    );
}

fn testRayIntersectsClosedCylinder(
    comptime T: type, allocator: Allocator, origin: Tuple(T), direction: Tuple(T), count: usize
) !void {
    var cyl = Shape(T).cylinder();

    cyl.variant.cylinder.min = 1.0;
    cyl.variant.cylinder.max = 2.0;
    cyl.variant.cylinder.closed = true;

    const r = Ray(T).new(origin, direction.normalized());

    const xs = try cyl.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, count);
}

test "Intersecting the caps of a closed cylinder" {
    const allocator = testing.allocator;

    // Use f64 for this test because of precision needs.
    try testRayIntersectsClosedCylinder(
        f64, allocator, Tuple(f64).point(0.0, 3.0, 0.0), Tuple(f64).vec3(0.0, -1.0, 0.0), 2
    );

    try testRayIntersectsClosedCylinder(
        f64, allocator, Tuple(f64).point(0.0, 3.0, -2.0), Tuple(f64).vec3(0.0, -1.0, 2.0), 2
    );

    try testRayIntersectsClosedCylinder(
        f64, allocator, Tuple(f64).point(0.0, 4.0, -2.0), Tuple(f64).vec3(0.0, -1.0, 1.0), 2
    );

    try testRayIntersectsClosedCylinder(
        f64, allocator, Tuple(f64).point(0.0, 0.0, -2.0), Tuple(f64).vec3(0.0, 1.0, 2.0), 2
    );

    try testRayIntersectsClosedCylinder(
        f64, allocator, Tuple(f64).point(0.0, -1.0, -2.0), Tuple(f64).vec3(0.0, 1.0, 1.0), 2
    );
}

fn testNormalOnClosedCylinder(comptime T: type, point: Tuple(T), normal: Tuple(T)) !void {
    var cyl = Shape(T).cylinder();

    cyl.variant.cylinder.min = 1.0;
    cyl.variant.cylinder.max = 2.0;
    cyl.variant.cylinder.closed = true;

    try testing.expect(cyl.normalAt(point, undefined).approxEqual(normal));
}

test "The normal vector on a cylinder's end caps" {
    try testNormalOnClosedCylinder(
        f32, Tuple(f32).point(0.0, 1.0, 0.0), Tuple(f32).vec3(0.0, -1.0, 0.0)
    );

    try testNormalOnClosedCylinder(
        f32, Tuple(f32).point(0.5, 1.0, 0.0), Tuple(f32).vec3(0.0, -1.0, 0.0)
    );

    try testNormalOnClosedCylinder(
        f32, Tuple(f32).point(0.0, 1.0, 0.5), Tuple(f32).vec3(0.0, -1.0, 0.0)
    );

    try testNormalOnClosedCylinder(
        f32, Tuple(f32).point(0.0, 2.0, 0.0), Tuple(f32).vec3(0.0, 1.0, 0.0)
    );

    try testNormalOnClosedCylinder(
        f32, Tuple(f32).point(0.5, 2.0, 0.0), Tuple(f32).vec3(0.0, 1.0, 0.0)
    );

    try testNormalOnClosedCylinder(
        f32, Tuple(f32).point(0.0, 2.0, 0.5), Tuple(f32).vec3(0.0, 1.0, 0.0)
    );
}

test "An unbounded cylinder has a bounding box" {
    const s = Shape(f32).cylinder();
    const box = s.bounds();

    try testing.expectEqual(box.variant.bounding_box.min, Tuple(f32).point(-1.0, -inf(f32), -1.0));
    try testing.expectEqual(box.variant.bounding_box.max, Tuple(f32).point(1.0, inf(f32), 1.0));
}

test "A bounded cylinder has a bounding box" {
    var s = Shape(f32).cylinder();
    s.variant.cylinder.min = -5.0;
    s.variant.cylinder.max = 3.0;
    
    const box = s.bounds();

    try testing.expectEqual(box.variant.bounding_box.min, Tuple(f32).point(-1.0, -5.0, -1.0));
    try testing.expectEqual(box.variant.bounding_box.max, Tuple(f32).point(1.0, 3.0, 1.0));
}
