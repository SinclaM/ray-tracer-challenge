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

/// A cylinder object, backed by floats of type `T`.
///
/// All cylinders are axis-aligned and centered at the origin in their
/// own object space. To move them, rotate them, resize them, etc.
/// in world space, use Shape.setTransform.
pub fn Cylinder(comptime T: type) type {
    return struct {
        const Self = @This();
        const tolerance: T = 1e-4;

        pub fn localIntersect(
            self: Self, allocator: Allocator, super: *const Shape(T), ray: Ray(T)
        ) !Intersections(T) {
            _ = self;
            const a = ray.direction.x * ray.direction.x + ray.direction.z * ray.direction.z;

            var xs = Intersections(T).init(allocator);

            if (@fabs(a) < Self.tolerance) {
                // Ray is parallel to y-axis
                return xs;
            }

            const b = 2.0 * ray.origin.x * ray.direction.x + 2.0 * ray.origin.z * ray.direction.z;
            const c = ray.origin.x * ray.origin.x + ray.origin.z * ray.origin.z - 1.0;

            const discriminant = b * b - 4.0 * a * c;

            if (discriminant < 0.0) {
                // Ray does not intersect
                return xs;
            }

            const t0 = (-b - @sqrt(discriminant)) / (2.0 * a);
            const t1 = (-b + @sqrt(discriminant)) / (2.0 * a);

            try xs.append(Intersection(T).new(t0, super));
            try xs.append(Intersection(T).new(t1, super));

            return xs;
        }

        pub fn localNormalAt(self: Self, super: Shape(T), point: Tuple(T)) Tuple(T) {
            _ = self;
            _ = super;

            return Tuple(T).vec3(point.x, 0.0, point.z);
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
    var cyl = Shape(f32).cylinder();
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
        f32, allocator, Tuple(f32).point(0.5, 0.0, -5.0), Tuple(f32).vec3(0.1, 1.0, 1.0), 6.80798, 7.08872
    );
}

fn testNormalOnCylinder(comptime T: type, point: Tuple(f32), normal: Tuple(f32)) !void {
    var cyl = Shape(T).cylinder();
    try testing.expect(cyl.normalAt(point).approxEqual(normal));
}

test "Normal vector on a cylinder" {
    try testNormalOnCylinder (
        f32, Tuple(f32).point(1.0, 0.0, 0.0), Tuple(f32).vec3(1.0, 0.0, 0.0)
    );

    try testNormalOnCylinder (
        f32, Tuple(f32).point(0.0, 5.0, -1.0), Tuple(f32).vec3(0.0, 0.0, -1.0)
    );

    try testNormalOnCylinder (
        f32, Tuple(f32).point(0.0, -2.0, 1.0), Tuple(f32).vec3(0.0, 0.0, 1.0)
    );

    try testNormalOnCylinder (
        f32, Tuple(f32).point(-1.0, 1.0, 0.0), Tuple(f32).vec3(-1.0, 0.0, 0.0)
    );
}
