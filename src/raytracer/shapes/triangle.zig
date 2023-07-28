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
const Shape = shape.Shape;
const PreComputations = @import("../world.zig").PreComputations;

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

        pub fn localNormalAt(self: Self, point: Tuple(T), hit: Intersection(T)) Tuple(T) {
            _ = point;
            _ = hit;

            return self.normal;
        }

        pub fn bounds(self: Self, super: *const Shape(T)) Shape(T) {
            _ = super;

            var box = Shape(T).boundingBox();
            box.variant.bounding_box.add(self.p1);
            box.variant.bounding_box.add(self.p2);
            box.variant.bounding_box.add(self.p3);

            return box;
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

    const n1 = t.normalAt(Tuple(f32).point(0.0, 0.5, 0.0), undefined);
    const n2 = t.normalAt(Tuple(f32).point(-0.5, 0.75, 0.0), undefined);
    const n3 = t.normalAt(Tuple(f32).point(0.5, 0.25, 0.0), undefined);

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

test "A triangle has a bounding box" {
    const s = Shape(f32).triangle(
        Tuple(f32).point(-3.0, 7.0, 2.0),
        Tuple(f32).point(6.0, 2.0, -4.0),
        Tuple(f32).point(2.0, -1.0, -1.0)
    );
    const box = s.bounds();

    try testing.expectEqual(box.variant.bounding_box.min, Tuple(f32).point(-3.0, -1.0, -4.0));
    try testing.expectEqual(box.variant.bounding_box.max, Tuple(f32).point(6.0, 7.0, 2.0));
}

/// A triangle object using normal interpolation, backed by floats of type `T`.
pub fn SmoothTriangle(comptime T: type) type {
    return struct {
        const Self = @This();
        const tolerance = 1e-5;

        p1: Tuple(T),
        p2: Tuple(T),
        p3: Tuple(T),
        e1: Tuple(T),
        e2: Tuple(T),
        n1: Tuple(T),
        n2: Tuple(T),
        n3: Tuple(T),

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
            try xs.append(Intersection(T).uvNew(t, super, u, v));

            return xs;
        }

        pub fn localNormalAt(self: Self, point: Tuple(T), hit: Intersection(T)) Tuple(T) {
            _ = point;

            return self.n2.mul(hit.u).add(self.n3.mul(hit.v)).add(self.n1.mul(1.0 - hit.u - hit.v));
        }

        pub fn bounds(self: Self, super: *const Shape(T)) Shape(T) {
            _ = super;

            var box = Shape(T).boundingBox();
            box.variant.bounding_box.add(self.p1);
            box.variant.bounding_box.add(self.p2);
            box.variant.bounding_box.add(self.p3);

            return box;
        }
    };
}

fn testSmoothTriangle(comptime T: type) Shape(T) {
    const p1 = Tuple(T).point(0.0, 1.0, 0.0);
    const p2 = Tuple(T).point(-1.0, 0.0, 0.0);
    const p3 = Tuple(T).point(1.0, 0.0, 0.0);
    const n1 = Tuple(T).vec3(0.0, 1.0, 0.0);
    const n2 = Tuple(T).vec3(-1.0, 0.0, 0.0);
    const n3 = Tuple(T).vec3(1.0, 0.0, 0.0);

    return Shape(T).smoothTriangle(p1, p2, p3, n1, n2, n3);
}

test "Constructing a smooth triangle" {
    const t = testSmoothTriangle(f32);
    const tri = &t.variant.smooth_triangle;

    try testing.expectEqual(tri.p1, Tuple(f32).point(0.0, 1.0, 0.0));
    try testing.expectEqual(tri.p2, Tuple(f32).point(-1.0, 0.0, 0.0));
    try testing.expectEqual(tri.p3, Tuple(f32).point(1.0, 0.0, 0.0));
    try testing.expectEqual(tri.n1, Tuple(f32).vec3(0.0, 1.0, 0.0));
    try testing.expectEqual(tri.n2, Tuple(f32).vec3(-1.0, 0.0, 0.0));
    try testing.expectEqual(tri.n3, Tuple(f32).vec3(1.0, 0.0, 0.0));
}

test "An intersection with a smooth triangle stores u/v" {
    const allocator = testing.allocator;

    const t = testSmoothTriangle(f32);

    const r = Ray(f32).new(
        Tuple(f32).point(-0.2, 0.3, -2.0), Tuple(f32).vec3(0.0, 0.0, 1.0)
    );

    const xs = try t.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectApproxEqAbs(xs.items[0].u, 0.45, SmoothTriangle(f32).tolerance);
    try testing.expectApproxEqAbs(xs.items[0].v, 0.25, SmoothTriangle(f32).tolerance);
}

test "A smooth triangle uses u/v to interpolate the normal" {
    const tri = testSmoothTriangle(f32);

    const i = Intersection(f32).uvNew(1.0, &tri, 0.45, 0.25);
    const n = tri.normalAt(Tuple(f32).point(0.0, 0.0, 0.0), i);
    try testing.expect(n.approxEqual(Tuple(f32).vec3(-0.5547, 0.83205, 0)));
}

test "Preparing the normal on a smooth triangle" {
    const allocator = testing.allocator;

    const tri = testSmoothTriangle(f32);

    const i = Intersection(f32).uvNew(1.0, &tri, 0.45, 0.25);

    const r = Ray(f32).new(
        Tuple(f32).point(-0.2, 0.3, -2.0), Tuple(f32).vec3(0.0, 0.0, 1.0)
    );

    var xs = Intersections(f32).init(allocator);
    defer xs.deinit();
    try xs.append(i);

    const comps = try PreComputations(f32).new(allocator, i, r, xs);
    try testing.expect(comps.normal.approxEqual(Tuple(f32).vec3(-0.5547, 0.83205, 0)));
}

test "A smooth triangle has a bounding box" {
    const s = Shape(f32).smoothTriangle(
        Tuple(f32).point(-3.0, 7.0, 2.0),
        Tuple(f32).point(6.0, 2.0, -4.0),
        Tuple(f32).point(2.0, -1.0, -1.0),
        undefined, // irrelevant
        undefined,
        undefined
    );
    const box = s.bounds();

    try testing.expectEqual(box.variant.bounding_box.min, Tuple(f32).point(-3.0, -1.0, -4.0));
    try testing.expectEqual(box.variant.bounding_box.max, Tuple(f32).point(6.0, 7.0, 2.0));
}

