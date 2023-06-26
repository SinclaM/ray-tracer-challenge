const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Ray = @import("../ray.zig").Ray;
const Material = @import("../material.zig").Material;

const shape = @import("shape.zig");
const Intersection = shape.Intersection;
const Intersections = shape.Intersections;
const sortIntersections = shape.sortIntersections;
const hit = shape.hit;
const Shape = shape.Shape;

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
                sortIntersections(T, &xs);
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

test "Id uniqueness" {
    var s1 = Shape(f32).sphere();
    var s2 = Shape(f32).sphere();
    try testing.expect(s1.id != s2.id);
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
        try testing.expectApproxEqAbs(first.t, 1.0, tolerance);
        try testing.expectApproxEqAbs(second.t, -1.0, tolerance);
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

test "Hit" {
    const allocator = testing.allocator;

    {
        var s = Shape(f32).sphere();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = 1.0, .object = s});
        try xs.append(.{ .t = 2.0, .object = s});

        try testing.expectEqual(hit(f32, xs), .{ .t = 1.0, .object = s});
    }

    {
        var s = Shape(f32).sphere();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = -1.0, .object = s});
        try xs.append(.{ .t = 1.0, .object = s});

        try testing.expectEqual(hit(f32, xs), .{ .t = 1.0, .object = s});
    }

    {
        var s = Shape(f32).sphere();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = -2.0, .object = s});
        try xs.append(.{ .t = -1.0, .object = s});

        try testing.expectEqual(hit(f32, xs), null);
    }

    {
        var s = Shape(f32).sphere();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = 5.0, .object = s});
        try xs.append(.{ .t = 7.0, .object = s});
        try xs.append(.{ .t = -3.0, .object = s});
        try xs.append(.{ .t = 2.0, .object = s});

        try testing.expectEqual(hit(f32, xs), .{ .t = 2.0, .object = s});
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
