const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Shape = @import("shape.zig").Shape;
const Intersection = @import("shape.zig").Intersection;
const Intersections = @import("shape.zig").Intersections;
const sortIntersections = @import("shape.zig").sortIntersections;
const Aligned = @import("shape.zig").Aligned;
const hit = @import("shape.zig").hit;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Ray = @import("../ray.zig").Ray;
const Material = @import("../material.zig").Material;

pub fn Sphere(comptime T: type) type {
    return extern struct {
        const Self = @This();

        shape: Shape(T),

        pub fn new() Self {
            return .{ .shape = Shape(T).new(Self.localIntersect, Self.localNormalAt) };
        }

        pub fn localIntersect(self: Aligned(T), allocator: Allocator, ray: Ray(T)) !Intersections(T) {
            const sphere = @ptrCast(*Self, self);
            const sphere_to_ray = ray.origin.sub(Tuple(T).point(0.0, 0.0, 0.0));

            const a = ray.direction.dot(ray.direction);
            const b = 2.0 * sphere_to_ray.dot(ray.direction);
            const c = sphere_to_ray.dot(sphere_to_ray) - 1.0;

            const discriminant = b * b - 4.0 * a * c;
            
            var xs = Intersections(T).init(allocator);
            if (discriminant >= 0.0) {
                const t1 = (-b - @sqrt(discriminant)) / (2.0 * a);
                const t2 = (-b + @sqrt(discriminant)) / (2.0 * a);

                try xs.append(Intersection(T).new(t1, sphere.shape));
                try xs.append(Intersection(T).new(t2, sphere.shape));
                sortIntersections(T, &xs);
            }
            return xs;
        }

        pub fn localNormalAt(self: Aligned(T), object_point: Tuple(T)) Tuple(T) {
            _ = self;
            return object_point.sub(Tuple(T).point(0.0, 0.0, 0.0));
        }
    };
}

test "Id uniqueness" {
    var s1 = Sphere(f32).new();
    var s2 = Sphere(f32).new();
    try testing.expect(s1.shape.id != s2.shape.id);
}

test "Intersections" {
    const tolerance = 1e-5;
    const allocator = testing.allocator;

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Sphere(f32).new();
        var xs = try s.shape.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first  = xs.items[0];
        const second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, 4.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 6.0, tolerance);
        try testing.expectEqual(first.object, s.shape);
        try testing.expectEqual(second.object, s.shape);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 1.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Sphere(f32).new();
        var xs = try s.shape.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first  = xs.items[0];
        const second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, 5.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 5.0, tolerance);
        try testing.expectEqual(first.object, s.shape);
        try testing.expectEqual(second.object, s.shape);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 2.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Sphere(f32).new();
        var xs = try s.shape.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 0);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Sphere(f32).new();
        var xs = try s.shape.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first =  xs.items[0];
        const second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, 1.0, tolerance);
        try testing.expectApproxEqAbs(second.t, -1.0, tolerance);
        try testing.expectEqual(first.object, s.shape);
        try testing.expectEqual(second.object, s.shape);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Sphere(f32).new();
        var xs = try s.shape.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first  = xs.items[0];
        const second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, -6.0, tolerance);
        try testing.expectApproxEqAbs(second.t, -4.0, tolerance);
        try testing.expectEqual(first.object, s.shape);
        try testing.expectEqual(second.object, s.shape);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Sphere(f32).new();
        try s.shape.setTransform(Matrix(f32, 4).identity().scale(2.0, 2.0, 2.0));
        var xs = try s.shape.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first =  xs.items[0];
        const second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, 3.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 7.0, tolerance);
        try testing.expectEqual(first.object, s.shape);
        try testing.expectEqual(second.object, s.shape);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var s = Sphere(f32).new();
        try s.shape.setTransform(Matrix(f32, 4).identity().translate(5.0, 0.0, 0.0));
        var xs = try s.shape.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 0);
    }
}

test "Hit" {
    const allocator = testing.allocator;

    {
        var s = Sphere(f32).new();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = 1.0, .object = s.shape });
        try xs.append(.{ .t = 2.0, .object = s.shape });

        try testing.expectEqual(hit(f32, xs), .{ .t = 1.0, .object = s.shape });
    }

    {
        var s = Sphere(f32).new();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = -1.0, .object = s.shape });
        try xs.append(.{ .t = 1.0, .object = s.shape });

        try testing.expectEqual(hit(f32, xs), .{ .t = 1.0, .object = s.shape });
    }

    {
        var s = Sphere(f32).new();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = -2.0, .object = s.shape });
        try xs.append(.{ .t = -1.0, .object = s.shape });

        try testing.expectEqual(hit(f32, xs), null);
    }

    {
        var s = Sphere(f32).new();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = 5.0, .object = s.shape });
        try xs.append(.{ .t = 7.0, .object = s.shape });
        try xs.append(.{ .t = -3.0, .object = s.shape });
        try xs.append(.{ .t = 2.0, .object = s.shape });

        try testing.expectEqual(hit(f32, xs), .{ .t = 2.0, .object = s.shape });
    }
}

test "Surface normals" {
    var s = Sphere(f32).new();
    try s.shape.setTransform(Matrix(f32, 4).identity().translate(0.0, 1.0, 0.0));
    var n = s.shape.normalAt(Tuple(f32).point(0, 1.70711, -0.70711));

    try testing.expect(n.approxEqual(Tuple(f32).vec3(0, 0.70711, -0.70711)));

    s = Sphere(f32).new();
    try s.shape.setTransform(Matrix(f32, 4).identity().rotateZ(std.math.pi / 5.0).scale(1.0, 0.5, 1.0));
    n = s.shape.normalAt(Tuple(f32).point(0.0, 1.0 / @sqrt(2.0), -1.0 / @sqrt(2.0)));

    try testing.expect(n.approxEqual(Tuple(f32).vec3(0, 0.97014, -0.24254)));
}
