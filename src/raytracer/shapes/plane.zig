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

/// A plane object, backed by floats of type `T`.
///
/// All planes are the xz plane in their own object space.
/// To move them, rotate them, resize them, etc. in world space,
/// use Shape.setTransform.
pub fn Plane(comptime T: type) type {
    return struct {
        const Self = @This();
        const epsilon: T = 1e-5;

        pub fn localIntersect(self: Self, allocator: Allocator, super: Shape(T), ray: Ray(T)) !Intersections(T) {
            _ = self;
            var xs = Intersections(T).init(allocator);

            if (@fabs(ray.direction.y) > Self.epsilon) {
                try xs.append(Intersection(T).new(-ray.origin.y / ray.direction.y, super));
            }

            return xs;
        }

        pub fn localNormalAt(self: Self, super: Shape(T), point: Tuple(T)) Tuple(T) {
            _ = self;
            _ = super;
            _ = point;
            return Tuple(T).vec3(0.0, 1.0, 0.0);
        }


    };
}

test "Intersections" {
    const allocator = testing.allocator;

    {
        var p = Shape(f32).plane();
        const r = Ray(f32).new(Tuple(f32).point(0.0, 10.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        const xs = try p.intersect(allocator, r);
        defer xs.deinit();
        try testing.expectEqual(xs.items.len, 0);
    }

    {
        var p = Shape(f32).plane();
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        const xs = try p.intersect(allocator, r);
        defer xs.deinit();
        try testing.expectEqual(xs.items.len, 0);
    }

    {
        var p = Shape(f32).plane();
        const r = Ray(f32).new(Tuple(f32).point(0.0, 1.0, 0.0), Tuple(f32).vec3(0.0, -1.0, 0.0));
        const xs = try p.intersect(allocator, r);
        defer xs.deinit();
        try testing.expectEqual(xs.items.len, 1);
        try testing.expectApproxEqAbs(xs.items[0].t, 1.0, Plane(f32).epsilon);
        try testing.expectEqual(xs.items[0].object, p);
    }

    {
        var p = Shape(f32).plane();
        const r = Ray(f32).new(Tuple(f32).point(0.0, -1.0, 0.0), Tuple(f32).vec3(0.0, 1.0, 0.0));
        const xs = try p.intersect(allocator, r);
        defer xs.deinit();
        try testing.expectEqual(xs.items.len, 1);
        try testing.expectApproxEqAbs(xs.items[0].t, 1.0, Plane(f32).epsilon);
        try testing.expectEqual(xs.items[0].object, p);
    }
}

test "Normals" {
    const p = Shape(f32).plane();
    const n1 = p.normalAt(Tuple(f32).point(0.0, 0.0, 0.0));
    const n2 = p.normalAt(Tuple(f32).point(10.0, 0.0, -10.0));
    const n3 = p.normalAt(Tuple(f32).point(-5.0, 0.0, 150.0));

    try testing.expect(n1.approxEqual(Tuple(f32).vec3(0.0, 1.0, 0.0)));
    try testing.expect(n2.approxEqual(Tuple(f32).vec3(0.0, 1.0, 0.0)));
    try testing.expect(n3.approxEqual(Tuple(f32).vec3(0.0, 1.0, 0.0)));
}
