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

/// A bounding box, backed by floats of type `T`.
pub fn BoundingBox(comptime T: type) type {
    return struct {
        const Self = @This();

        min: Tuple(T) = Tuple(T).point(inf(T), inf(T), inf(T)),
        max: Tuple(T) = Tuple(T).point(-inf(T), -inf(T), -inf(T)),

        pub fn add(self: *Self, point: Tuple(T)) void {
            self.min.x = @min(self.min.x, point.x);
            self.min.y = @min(self.min.y, point.y);
            self.min.z = @min(self.min.z, point.z);

            self.max.x = @max(self.max.x, point.x);
            self.max.y = @max(self.max.y, point.y);
            self.max.z = @max(self.max.z, point.z);
        }

        pub fn contains_point(self: Self, point: Tuple(T)) bool {
            return  self.min.x <= point.x and point.x <= self.max.x
                and self.min.y <= point.y and point.y <= self.max.y
                and self.min.z <= point.z and point.z <= self.max.z;
        }

        pub fn contains_box(self: Self, other: Self) bool {
            return self.contains_point(other.min) and self.contains_point(other.max);
        }

        pub fn merge(self: *Self, other: Self) void {
            self.add(other.min);
            self.add(other.max);
        }

        pub fn transform(self: Self, matrix: Matrix(T, 4)) Shape(T) {
            const p1 = self.min;
            const p2 = Tuple(T).point(self.min.x, self.min.y, self.max.z);
            const p3 = Tuple(T).point(self.min.x, self.max.y, self.min.z);
            const p4 = Tuple(T).point(self.min.x, self.max.y, self.max.z);
            const p5 = Tuple(T).point(self.max.x, self.min.y, self.min.z);
            const p6 = Tuple(T).point(self.max.x, self.min.y, self.max.z);
            const p7 = Tuple(T).point(self.max.x, self.max.y, self.min.z);
            const p8 = self.max;

            var new = Shape(T).boundingBox();
            new.variant.bounding_box.add(matrix.tupleMul(p1));
            new.variant.bounding_box.add(matrix.tupleMul(p2));
            new.variant.bounding_box.add(matrix.tupleMul(p3));
            new.variant.bounding_box.add(matrix.tupleMul(p4));
            new.variant.bounding_box.add(matrix.tupleMul(p5));
            new.variant.bounding_box.add(matrix.tupleMul(p6));
            new.variant.bounding_box.add(matrix.tupleMul(p7));
            new.variant.bounding_box.add(matrix.tupleMul(p8));

            return new;
        }

        pub fn split(self: Self) [2]Shape(T) {
            const dx = self.max.x - self.min.x;
            const dy = self.max.y - self.min.y;
            const dz = self.max.z - self.min.z;

            const greatest = @max(dx, @max(dy, dz));

            var x0 = self.min.x;
            var y0 = self.min.y;
            var z0 = self.min.z;

            var x1 = self.max.x;
            var y1 = self.max.y;
            var z1 = self.max.z;

            if (greatest == dx) {
                x0 = x0 + dx / 2.0;
                x1 = x0;
            } else if (greatest == dy) {
                y0 = y0 + dy / 2.0;
                y1 = y0;
            } else {
                z0 = z0 + dz / 2.0;
                z1 = z0;
            }

            const mid_min = Tuple(T).point(x0, y0, z0);
            const mid_max = Tuple(T).point(x1, y1, z1);

            var left = Shape(T).boundingBox();
            left.variant.bounding_box.min = self.min;
            left.variant.bounding_box.max = mid_max;

            var right = Shape(T).boundingBox();
            right.variant.bounding_box.min = mid_min;
            right.variant.bounding_box.max = self.max;

            return [_]Shape(T) { left, right };
        }

        fn checkAxis(origin: T, direction: T, min: T, max: T) [2]T {
            const epsilon = 1e-5;

            const tmin_numerator = min - origin;
            const tmax_numerator = max - origin;

            var tmin: T = 0.0;
            var tmax: T = 0.0;

            if (@abs(direction) >= epsilon) {
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

        pub fn localIntersect(
            self: Self, allocator: Allocator, super: *const Shape(T), ray: Ray(T)
        ) !Intersections(T) {
            const xt = Self.checkAxis(ray.origin.x, ray.direction.x, self.min.x, self.max.x);
            const xtmin = xt[0];
            const xtmax = xt[1];

            const yt = Self.checkAxis(ray.origin.y, ray.direction.y, self.min.y, self.max.y);
            const ytmin = yt[0];
            const ytmax = yt[1];

            const zt = Self.checkAxis(ray.origin.z, ray.direction.z, self.min.z, self.max.z);
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

        pub fn localNormalAt(self: Self, point: Tuple(T), hit: Intersection(T)) Tuple(T) {
            _ = self;
            _ = point;
            _ = hit;

            @panic("Unimplemented.");
        }

        pub fn bounds(self: Self) Shape(T) {
            _ = self;

            @panic("Unimplemented.");
        }
    };
}

test "Adding points to an empty bounding box" {
    var box = Shape(f32).boundingBox();

    box.variant.bounding_box.add(Tuple(f32).point(-5.0, 2.0, 0.0));
    box.variant.bounding_box.add(Tuple(f32).point(7.0, 0.0, -3.0));

    try testing.expectEqual(box.variant.bounding_box.min, Tuple(f32).point(-5.0, 0.0, -3.0));
    try testing.expectEqual(box.variant.bounding_box.max, Tuple(f32).point(7.0, 2.0, 0.0));
}

test "Checking to see if a box contains a given point" {
    var box = Shape(f32).boundingBox();

    box.variant.bounding_box.min = Tuple(f32).point(5.0, -2.0, 0.0);
    box.variant.bounding_box.max = Tuple(f32).point(11.0, 4.0, 7.0);

    try testing.expect(
        box.variant.bounding_box.contains_point(Tuple(f32).point(5.0, -2.0, 0.0))
    );
    try testing.expect(
        box.variant.bounding_box.contains_point(Tuple(f32).point(11.0, 4.0, 7.0))
    );
    try testing.expect(
        box.variant.bounding_box.contains_point(Tuple(f32).point(8.0, 1.0, 3.0))
    );
    try testing.expect(
        !box.variant.bounding_box.contains_point(Tuple(f32).point(3.0, 0.0, 3.0))
    );
    try testing.expect(
        !box.variant.bounding_box.contains_point(Tuple(f32).point(8.0, -4.0, 3.0))
    );
    try testing.expect(
        !box.variant.bounding_box.contains_point(Tuple(f32).point(8.0, 1.0, -1.0))
    );
    try testing.expect(
        !box.variant.bounding_box.contains_point(Tuple(f32).point(13.0, 1.0, 3.0))
    );
    try testing.expect(
        !box.variant.bounding_box.contains_point(Tuple(f32).point(8.0, 5.0, 3.0))
    );
    try testing.expect(
        !box.variant.bounding_box.contains_point(Tuple(f32).point(8.0, 1.0, 8.0))
    );
}

fn testBoxConstainsBox(comptime T: type, min: Tuple(T), max: Tuple(T), result: bool) !void {
    var box = Shape(f32).boundingBox();

    box.variant.bounding_box.min = Tuple(f32).point(5.0, -2.0, 0.0);
    box.variant.bounding_box.max = Tuple(f32).point(11.0, 4.0, 7.0);

    var box2 = Shape(f32).boundingBox();

    box2.variant.bounding_box.min = min;
    box2.variant.bounding_box.max = max;

    try testing.expectEqual(box.variant.bounding_box.contains_box(box2.variant.bounding_box), result);
}

test "Checking to see if a box contains a given box" {
    try testBoxConstainsBox(
        f32, Tuple(f32).point(5.0, -2.0, 0.0), Tuple(f32).point(11.0, 4.0, 7.0), true
    );
    try testBoxConstainsBox(
        f32, Tuple(f32).point(6.0, -1.0, 1.0), Tuple(f32).point(10.0, 3.0, 6.0), true
    );
    try testBoxConstainsBox(
        f32, Tuple(f32).point(4.0, -3.0, -1.0), Tuple(f32).point(10.0, 3.0, 6.0), false
    );
    try testBoxConstainsBox(
        f32, Tuple(f32).point(6.0, -1.0, 1.0), Tuple(f32).point(12.0, 5.0, 8.0), false
    );
}

test "Transforming a bounding box" {
    var box = Shape(f32).boundingBox();
    box.variant.bounding_box.min = Tuple(f32).point(-1.0, -1.0, -1.0);
    box.variant.bounding_box.max = Tuple(f32).point(1.0, 1.0, 1.0);

    const matrix = Matrix(f32, 4).identity().rotateY(std.math.pi / 4.0).rotateX(std.math.pi / 4.0);

    const box2 = box.variant.bounding_box.transform(matrix);

    try testing.expect(
        box2.variant.bounding_box.min.approxEqual(Tuple(f32).point(-1.41421, -1.7071, -1.7071))
    );
    try testing.expect(
        box2.variant.bounding_box.max.approxEqual(Tuple(f32).point(1.41421, 1.7071, 1.7071))
    );

}

fn testIntersectAABB(
    comptime T: type, allocator: Allocator, origin: Tuple(T), direction: Tuple(T), result: bool
) !void {
    var box = Shape(T).boundingBox();
    box.variant.bounding_box.min = Tuple(T).point(-1.0, -1.0, -1.0);
    box.variant.bounding_box.max = Tuple(T).point(1.0, 1.0, 1.0);
    const r = Ray(T).new(origin, direction.normalized());

    const xs = try box.intersect(allocator, r);
    defer xs.deinit();

    try testing.expect((xs.items.len > 0) == result);
}

test "Intersecting a ray with a bounding box at the origin" {
    const allocator = testing.allocator;

    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(5.0, 0.5, 0.0), Tuple(f32).vec3(-1.0, 0.0, 0.0), true
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(-5.0, 0.5, 0.0), Tuple(f32).vec3(1.0, 0.0, 0.0), true
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(0.5, -5.0, 0.0), Tuple(f32).vec3(0.0, -1.0, 0.0), true
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(0.5, -5.0, 0.0), Tuple(f32).vec3(0.0, 1.0, 0.0), true
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(0.5, 0.0, 5.0), Tuple(f32).vec3(0.0, 0.0, -1.0), true
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(0.5, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0), true
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(0.0, 0.5, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0), true
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(-2.0, 0.0, 0.0), Tuple(f32).vec3(2.0, 4.0, 6.0), false
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(0.0, -2.0, 0.0), Tuple(f32).vec3(6.0, 2.0, 4.0), false
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(0.0, 0.0, -2.0), Tuple(f32).vec3(4.0, 6.0, 2.0), false
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(2.0, 0.0, 2.0), Tuple(f32).vec3(0.0, 0.0, -1.0), false
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(0.0, 2.0, 2.0), Tuple(f32).vec3(0.0, -1.0, 0.0), false
    );
    try testIntersectAABB(
        f32, allocator, Tuple(f32).point(2.0, 2.0, 0.0), Tuple(f32).vec3(-1.0, 0.0, 0.0), false
    );
}

fn testIntersectNonCubicAABB(
    comptime T: type, allocator: Allocator, origin: Tuple(T), direction: Tuple(T), result: bool
) !void {
    var box = Shape(T).boundingBox();
    box.variant.bounding_box.min = Tuple(T).point(5.0, -2.0, 0.0);
    box.variant.bounding_box.max = Tuple(T).point(11.0, 4.0, 7.0);
    const r = Ray(T).new(origin, direction.normalized());

    const xs = try box.intersect(allocator, r);
    defer xs.deinit();

    try testing.expect((xs.items.len > 0) == result);
}

test "Intersecting a ray with a non-cubic bounding box" {
    const allocator = testing.allocator;

    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(15, 1, 2), Tuple(f32).vec3(-1, 0, 0), true);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(-5, -1, 4), Tuple(f32).vec3(1, 0, 0), true);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(7, 6, 5), Tuple(f32).vec3(0, -1, 0), true);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(9, -5, 6), Tuple(f32).vec3(0, 1, 0), true);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(8, 2, 12), Tuple(f32).vec3(0, 0, -1), true);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(6, 0, -5), Tuple(f32).vec3(0, 0, 1), true);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(8, 1, 3.5), Tuple(f32).vec3(0, 0, 1), true);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(9, -1, -8), Tuple(f32).vec3(2, 4, 6), false);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(8, 3, -4), Tuple(f32).vec3(6, 2, 4), false);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(9, -1, -2), Tuple(f32).vec3(4, 6, 2), false);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(4, 0, 9), Tuple(f32).vec3(0, 0, -1), false);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(8, 6, -1), Tuple(f32).vec3(0, -1, 0), false);
    try testIntersectNonCubicAABB(f32, allocator, Tuple(f32).point(12, 5, 4), Tuple(f32).vec3(-1, 0, 0), false);
}

test "Splitting a perfect cube" {
    var box = Shape(f32).boundingBox();
    box.variant.bounding_box.min = Tuple(f32).point(-1.0, -4.0, -5.0);
    box.variant.bounding_box.max = Tuple(f32).point(9.0, 6.0, 5.0);

    const split = box.variant.bounding_box.split();
    const left = &split[0].variant.bounding_box;
    const right = &split[1].variant.bounding_box;

    try testing.expectEqual(left.min, Tuple(f32).point(-1.0, -4.0, -5.0));
    try testing.expect(left.max.approxEqual(Tuple(f32).point(4.0, 6.0, 5.0)));
    try testing.expect(right.min.approxEqual(Tuple(f32).point(4.0, -4.0, -5.0)));
    try testing.expectEqual(right.max, Tuple(f32).point(9.0, 6.0, 5.0));
}

test "Splitting an x-wide box" {
    var box = Shape(f32).boundingBox();
    box.variant.bounding_box.min = Tuple(f32).point(-1.0, -2.0, -3.0);
    box.variant.bounding_box.max = Tuple(f32).point(9.0, 5.5, 3.0);

    const split = box.variant.bounding_box.split();
    const left = &split[0].variant.bounding_box;
    const right = &split[1].variant.bounding_box;

    try testing.expectEqual(left.min, Tuple(f32).point(-1.0, -2.0, -3.0));
    try testing.expect(left.max.approxEqual(Tuple(f32).point(4.0, 5.5, 3.0)));
    try testing.expect(right.min.approxEqual(Tuple(f32).point(4.0, -2.0, -3.0)));
    try testing.expectEqual(right.max, Tuple(f32).point(9.0, 5.5, 3.0));
}

test "Splitting a y-wide box" {
    var box = Shape(f32).boundingBox();
    box.variant.bounding_box.min = Tuple(f32).point(-1.0, -2.0, -3.0);
    box.variant.bounding_box.max = Tuple(f32).point(5.0, 8.0, 3.0);

    const split = box.variant.bounding_box.split();
    const left = &split[0].variant.bounding_box;
    const right = &split[1].variant.bounding_box;

    try testing.expectEqual(left.min, Tuple(f32).point(-1.0, -2.0, -3.0));
    try testing.expect(left.max.approxEqual(Tuple(f32).point(5.0, 3.0, 3.0)));
    try testing.expect(right.min.approxEqual(Tuple(f32).point(-1.0, 3.0, -3.0)));
    try testing.expectEqual(right.max, Tuple(f32).point(5.0, 8.0, 3.0));
}

test "Splitting a z-wide box" {
    var box = Shape(f32).boundingBox();
    box.variant.bounding_box.min = Tuple(f32).point(-1.0, -2.0, -3.0);
    box.variant.bounding_box.max = Tuple(f32).point(5.0, 3.0, 7.0);

    const split = box.variant.bounding_box.split();
    const left = &split[0].variant.bounding_box;
    const right = &split[1].variant.bounding_box;

    try testing.expectEqual(left.min, Tuple(f32).point(-1.0, -2.0, -3.0));
    try testing.expect(left.max.approxEqual(Tuple(f32).point(5.0, 3.0, 2.0)));
    try testing.expect(right.min.approxEqual(Tuple(f32).point(-1.0, -2.0, 2.0)));
    try testing.expectEqual(right.max, Tuple(f32).point(5.0, 3.0, 7.0));
}
