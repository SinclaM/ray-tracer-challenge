const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Ray = @import("../ray.zig").Ray;
const Material = @import("../material.zig").Material;

pub fn Intersection(comptime T: type) type {
    return struct {
        const Self = @This();
        t: T,
        object: Sphere(T),

        pub fn new(t: T, object: Sphere(T)) Self {
            return .{ .t = t, .object = object };
        }
    };

}

fn IntersectionCmp(comptime T: type) type {
    return struct {
        fn call(context: void, a: Intersection(T), b: Intersection(T)) bool {
            _ = context;

            if (a.t > 0.0 and b.t < 0.0) {
                return true;
            } else if (a.t < 0.0 and b.t > 0.0) {
                return false;
            }

            return std.sort.asc(T)({}, a.t, b.t);
        }
    };
}

pub fn Intersections(comptime T: type) type {
    return ArrayList(Intersection(T));
}


pub fn sortIntersections(comptime T: type, intersections: *Intersections(T)) void {
    std.sort.sort(Intersection(T), intersections.items[0..], {}, IntersectionCmp(T).call);
}

pub fn hit(comptime T: type, intersections: Intersections(T)) ?Intersection(T) {
    var min: ?Intersection(T) = null;

    for (intersections.items) |item| {
        if (min) |_| {
            if (IntersectionCmp(T).call({}, item, min.?)) {
                min = item;
            }
        } else if (item.t >= 0.0) {
            min = item;
        }
    }

    return min;
}

pub fn Sphere(comptime T: type) type {
    return struct {
        const Self = @This();

        id: usize,
        transform: Matrix(f32, 4) = Matrix(f32, 4).identity(),
        inverse_transform: Matrix(f32, 4) = Matrix(f32, 4).identity(),
        inverse_transform_transpose: Matrix(f32, 4) = Matrix(f32, 4).identity(),
        material: Material(T) = Material(T).new(),

        pub fn new() Self {
            const static = struct {
                var id: usize = 0;
            };

            const save = static.id;
            static.id += 1;

            return .{ .id = save };
        }

        pub fn set_transform(self: *Self, matrix: Matrix(T, 4)) !void {
            self.transform = matrix;
            self.inverse_transform = try self.transform.inverse();
            self.inverse_transform_transpose = self.inverse_transform.transpose();
        }

        pub fn intersect(self: Self, allocator: Allocator, ray: Ray(T)) !Intersections(T) {
            const ray_tr = ray.transform(self.inverse_transform);
            const sphere_to_ray_tr = ray_tr.origin.sub(Tuple(T).new_point(0.0, 0.0, 0.0));

            const a = ray_tr.direction.dot(ray_tr.direction);
            const b = 2.0 * sphere_to_ray_tr.dot(ray_tr.direction);
            const c = sphere_to_ray_tr.dot(sphere_to_ray_tr) - 1.0;

            const discriminant = b * b - 4.0 * a * c;
            
            var xs = Intersections(T).init(allocator);
            if (discriminant >= 0.0) {
                const t1 = (-b - @sqrt(discriminant)) / (2.0 * a);
                const t2 = (-b + @sqrt(discriminant)) / (2.0 * a);

                try xs.append(Intersection(T).new(t1, self));
                try xs.append(Intersection(T).new(t2, self));
                sortIntersections(T, &xs);
            }
            return xs;
        }

        pub fn normal_at(self: Self, world_point: Tuple(T)) Tuple(T) {
            const inv_transform = self.inverse_transform;
            const object_point = inv_transform.tupleMul(world_point);
            const object_normal = object_point.sub(Tuple(T).new_point(0.0, 0.0, 0.0));
            var world_normal = self.inverse_transform_transpose.tupleMul(object_normal);
            world_normal.w = 0.0;
            return world_normal.normalized();
        }
    };
}

test "Id uniqueness" {
    var s1 = Sphere(f32).new();
    var s2 = Sphere(f32).new();
    try testing.expect(s1.id != s2.id);
}

test "Intersections" {
    const tolerance = 1e-5;
    const allocator = testing.allocator;

    {
        const r = Ray(f32).new(Tuple(f32).new_point(0.0, 0.0, -5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
        const s = Sphere(f32).new();
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first  = xs.items[0];
        const second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, 4.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 6.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).new_point(0.0, 1.0, -5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
        const s = Sphere(f32).new();
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first  = xs.items[0];
        const second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, 5.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 5.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).new_point(0.0, 2.0, -5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
        const s = Sphere(f32).new();
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 0);
    }

    {
        const r = Ray(f32).new(Tuple(f32).new_point(0.0, 0.0, 0.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
        const s = Sphere(f32).new();
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first =  xs.items[0];
        const second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, 1.0, tolerance);
        try testing.expectApproxEqAbs(second.t, -1.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).new_point(0.0, 0.0, 5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
        const s = Sphere(f32).new();
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first  = xs.items[0];
        const second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, -6.0, tolerance);
        try testing.expectApproxEqAbs(second.t, -4.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).new_point(0.0, 0.0, -5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
        var s = Sphere(f32).new();
        try s.set_transform(Matrix(f32, 4).identity().scale(2.0, 2.0, 2.0));
        var xs = try s.intersect(allocator, r);
        defer xs.deinit();

        try testing.expectEqual(xs.items.len, 2);

        const first =  xs.items[0];
        const second = xs.items[1];
        try testing.expectApproxEqAbs(first.t, 3.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 7.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).new_point(0.0, 0.0, -5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
        var s = Sphere(f32).new();
        try s.set_transform(Matrix(f32, 4).identity().translate(5.0, 0.0, 0.0));
        var xs = try s.intersect(allocator, r);
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
        try xs.append(.{ .t = 1.0, .object = s});
        try xs.append(.{ .t = 2.0, .object = s});

        try testing.expectEqual(hit(f32, xs), .{ .t = 1.0, .object = s});
    }

    {
        var s = Sphere(f32).new();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = -1.0, .object = s});
        try xs.append(.{ .t = 1.0, .object = s});

        try testing.expectEqual(hit(f32, xs), .{ .t = 1.0, .object = s});
    }

    {
        var s = Sphere(f32).new();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = -2.0, .object = s});
        try xs.append(.{ .t = -1.0, .object = s});

        try testing.expectEqual(hit(f32, xs), null);
    }

    {
        var s = Sphere(f32).new();
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
    var s = Sphere(f32).new();
    try s.set_transform(Matrix(f32, 4).identity().translate(0.0, 1.0, 0.0));
    var n = s.normal_at(Tuple(f32).new_point(0, 1.70711, -0.70711));

    try testing.expect(n.approx_equal(Tuple(f32).new_vec3(0, 0.70711, -0.70711)));

    s = Sphere(f32).new();
    try s.set_transform(Matrix(f32, 4).identity().rotate_z(std.math.pi / 5.0).scale(1.0, 0.5, 1.0));
    n = s.normal_at(Tuple(f32).new_point(0.0, 1.0 / @sqrt(2.0), -1.0 / @sqrt(2.0)));

    try testing.expect(n.approx_equal(Tuple(f32).new_vec3(0, 0.97014, -0.24254)));
}
