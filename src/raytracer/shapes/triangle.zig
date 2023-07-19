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

/// A triangle object, backed by floats of type `T`.
pub fn Triangle(comptime T: type) type {
    return struct {
        const Self = @This();
        const tolerance = 1e-5;

        p1: Tuple(T),
        p2: Tuple(T),
        p3: Tuple(T),
        e1: Tuple(T),
        e2: Tuple(T),
        normal: Tuple(T),

        pub fn localIntersect(
            self: Self, allocator: Allocator, super: *const Shape(T), ray: Ray(T)
        ) !Intersections(T) {
            var xs = Intersections(T).init(allocator);

            const dir_cross_e2 = ray.direction.cross(self.e2);
            const det = self.e1.dot(dir_cross_e2);

            if (@fabs(det) < Self.tolerance) {
                // The ray is parallel and misses.
                return xs;
            }

            const f = 1.0 / det;
            const p1_to_origin = ray.origin.sub(self.p1);
            const u = f * p1_to_origin.dot(dir_cross_e2);

            if (u < 0.0 or u > 1.0) {
                // The ray passes beyond the p1-p3 edge and misses.
                return xs;
            }

            const p1_to_origin_cross_e1 = p1_to_origin.cross(self.e1);
            const v = f * ray.direction.dot(p1_to_origin_cross_e1);

            if (v < 0.0 or (u + v) > 1.0) {
                // The ray passes beyond the p1-p2 or the p2-p3 edge and misses.
                return xs;
            }

            const t = f * self.e2.dot(p1_to_origin_cross_e1);
            try xs.append(Intersection(T).new(t, super));

            return xs;
        }

        pub fn localNormalAt(self: Self, super: Shape(T), point: Tuple(T)) Tuple(T) {
            _ = super;
            _ = point;

            return self.normal;
        }
    };
}

test "Constructing a triangle" {
    const p1 = Tuple(f32).point(0.0, 1.0, 0.0);
    const p2 = Tuple(f32).point(-1.0, 0.0, 0.0);
    const p3 = Tuple(f32).point(1.0, 0.0, 0.0);

    const t = Shape(f32).triangle(p1, p2, p3);

    const triangle = &t.variant.triangle;

    try testing.expect(triangle.p1.approxEqual(p1));
    try testing.expect(triangle.p2.approxEqual(p2));
    try testing.expect(triangle.p3.approxEqual(p3));

    try testing.expect(triangle.e1.approxEqual(Tuple(f32).vec3(-1.0, -1.0, 0.0)));
    try testing.expect(triangle.e2.approxEqual(Tuple(f32).vec3(1.0, -1.0, 0.0)));
    try testing.expect(triangle.normal.approxEqual(Tuple(f32).vec3(0.0, 0.0, -1.0)));
}

test "Finding the normal on a triangle" {
    const t = Shape(f32).triangle(
        Tuple(f32).point(0.0, 1.0, 0.0),
        Tuple(f32).point(-1.0, 0.0, 0.0),
        Tuple(f32).point(1.0, 0.0, 0.0),
    );

    const n1 = t.normalAt(Tuple(f32).point(0.0, 0.5, 0.0));
    const n2 = t.normalAt(Tuple(f32).point(-0.5, 0.75, 0.0));
    const n3 = t.normalAt(Tuple(f32).point(0.5, 0.25, 0.0));

    try testing.expectEqual(n1, t.variant.triangle.normal);
    try testing.expectEqual(n2, t.variant.triangle.normal);
    try testing.expectEqual(n3, t.variant.triangle.normal);
}

test "Intersecting a ray parallel to the triangle" {
    const allocator = testing.allocator;

    const t = Shape(f32).triangle(
        Tuple(f32).point(0.0, 1.0, 0.0),
        Tuple(f32).point(-1.0, 0.0, 0.0),
        Tuple(f32).point(1.0, 0.0, 0.0),
    );

    const r = Ray(f32).new(Tuple(f32).point(0.0, -1.0, -2.0), Tuple(f32).vec3(0.0, 1.0, 0.0));
    const xs = try t.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 0);
}

test "A ray misses the p1-p3 edge" {
    const allocator = testing.allocator;

    const t = Shape(f32).triangle(
        Tuple(f32).point(0.0, 1.0, 0.0),
        Tuple(f32).point(-1.0, 0.0, 0.0),
        Tuple(f32).point(1.0, 0.0, 0.0),
    );

    const r = Ray(f32).new(Tuple(f32).point(1.0, 1.0, -2.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
    const xs = try t.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 0);
}

test "A ray misses the p1-p2 edge" {
    const allocator = testing.allocator;

    const t = Shape(f32).triangle(
        Tuple(f32).point(0.0, 1.0, 0.0),
        Tuple(f32).point(-1.0, 0.0, 0.0),
        Tuple(f32).point(1.0, 0.0, 0.0),
    );

    const r = Ray(f32).new(Tuple(f32).point(-1.0, 1.0, -2.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
    const xs = try t.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 0);
}

test "A ray misses the p2-p3 edge" {
    const allocator = testing.allocator;

    const t = Shape(f32).triangle(
        Tuple(f32).point(0.0, 1.0, 0.0),
        Tuple(f32).point(-1.0, 0.0, 0.0),
        Tuple(f32).point(1.0, 0.0, 0.0),
    );

    const r = Ray(f32).new(Tuple(f32).point(0.0, -1.0, -2.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
    const xs = try t.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 0);
}

test "A ray strikes a triangle" {
    const allocator = testing.allocator;

    const t = Shape(f32).triangle(
        Tuple(f32).point(0.0, 1.0, 0.0),
        Tuple(f32).point(-1.0, 0.0, 0.0),
        Tuple(f32).point(1.0, 0.0, 0.0),
    );

    const r = Ray(f32).new(Tuple(f32).point(0.0, 0.5, -2.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
    const xs = try t.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 1);
    try testing.expectEqual(xs.items[0].t, 2.0);
}
