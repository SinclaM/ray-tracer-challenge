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

/// A sphere object, backed by floats of type `T`.
///
/// All spheres are unit spheres centered at the origin in their
/// own object space. To move them, rotate them, resize them, etc.
/// in world space, use Shape.setTransform.
pub fn Sphere(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn localIntersect(self: Self, allocator: Allocator, super: Shape(T), ray: Ray(T)) !Intersections(T) {
            _ = self;
            const sphere_to_ray = ray.origin.sub(Tuple(T).point(0.0, 0.0, 0.0));

            const a = ray.direction.dot(ray.direction);
            const b = 2.0 * sphere_to_ray.dot(ray.direction);
            const c = sphere_to_ray.dot(sphere_to_ray) - 1.0;

            const discriminant = b * b - 4.0 * a * c;
            
            var xs = Intersections(T).init(allocator);
            if (discriminant >= 0.0) {
                const t1 = (-b - @sqrt(discriminant)) / (2.0 * a);
                const t2 = (-b + @sqrt(discriminant)) / (2.0 * a);

                try xs.append(Intersection(T).new(t1, super));
                try xs.append(Intersection(T).new(t2, super));
                sortIntersections(T, xs.items);
            }
            return xs;
        }

        pub fn localNormalAt(self: Self, super: Shape(T), point: Tuple(T)) Tuple(T) {
            _ = self;
            _ = super;
            const ret = point.sub(Tuple(T).point(0.0, 0.0, 0.0));
            return ret;
        }
    };
}

test "Intersections" {
    const tolerance = 1e-5;
    const allocator = testing.allocator;

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Shape(f32).sphere();
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first  = xs.items[0];
        var second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, 4.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 6.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 1.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Shape(f32).sphere();
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first  = xs.items[0];
        var second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, 5.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 5.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 2.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Shape(f32).sphere();
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 0);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Shape(f32).sphere();
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first =  xs.items[0];
        var second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, -1.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 1.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Shape(f32).sphere();
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first  = xs.items[0];
        var second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, -6.0, tolerance);
        try testing.expectApproxEqAbs(second.t, -4.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Shape(f32).sphere();
        try s.setTransform(Matrix(f32, 4).identity().scale(2.0, 2.0, 2.0));
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first =  xs.items[0];
        var second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, 3.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 7.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Shape(f32).sphere();
        try s.setTransform(Matrix(f32, 4).identity().translate(5.0, 0.0, 0.0));
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 0);
    }
}

test "Surface normals" {
    var s = Shape(f32).sphere();
    try s.setTransform(Matrix(f32, 4).identity().translate(0.0, 1.0, 0.0));
    var n = s.normalAt(Tuple(f32).point(0, 1.70711, -0.70711));

    try testing.expect(n.approxEqual(Tuple(f32).vec3(0, 0.70711, -0.70711)));

    s = Shape(f32).sphere();
    try s.setTransform(Matrix(f32, 4).identity().rotateZ(std.math.pi / 5.0).scale(1.0, 0.5, 1.0));
    n = s.normalAt(Tuple(f32).point(0.0, 1.0 / @sqrt(2.0), -1.0 / @sqrt(2.0)));

    try testing.expect(n.approxEqual(Tuple(f32).vec3(0, 0.97014, -0.24254)));
}
