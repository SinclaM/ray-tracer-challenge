const std = @import("std");
const testing = std.testing;
const Alloctor = std.mem.Allocator;
const PriorityQueue = std.PriorityQueue;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const MatrixError = @import("../matrix.zig").MatrixError;
const Ray = @import("../ray.zig").Ray;
const Material = @import("../material.zig").Material;

pub fn Intersection(comptime T: type) type {
    return struct {
        t: T,
        object: Sphere(T),
    };
}

fn IntersectionOrder(comptime T: type) type {
    return struct {
        fn lessThan(context: void, a: Intersection(T), b: Intersection(T)) std.math.Order { 
            _ = context;

            if (a.t > 0.0 and b.t < 0.0) {
                return std.math.Order.lt;
            }

            return std.math.order(a.t, b.t);
        }
    };
}

pub fn Intersections(comptime T: type) type {
    return struct {
        const Self = @This();
        const QueueType = PriorityQueue(Intersection(T), void, IntersectionOrder(T).lessThan);
        queue: QueueType,

        pub fn new(allocator: Alloctor) Self {
            return .{ .queue = QueueType.init(allocator, {}) };
        }

        pub fn destroy(self: Self) void {
            self.queue.deinit();
        }

        pub fn peek(self: *Self) @TypeOf(self.queue.peek()) {
            return self.queue.peek();
        }

        pub fn add(self: *Self, elem: Intersection(T)) @TypeOf(self.queue.add(elem)) {
            return self.queue.add(elem);
        }

        pub fn iterator(self: *Self) @TypeOf(self.queue.iterator()) {
            return self.queue.iterator();
        }

        pub fn count(self: *Self) @TypeOf(self.queue.count()) {
            return self.queue.count();
        }

        pub fn hit(intersections: *Intersections(T)) ?Intersection(T) {
            const maybe_top = intersections.peek();
            if (maybe_top) |top| {
                if (top.t < 0.0) {
                    return null;
                }
            }

            return maybe_top;
        }
    };

}

pub fn Sphere(comptime T: type) type {
    return struct {
        const Self = @This();

        id: usize,
        transform: Matrix(f32, 4) = Matrix(f32, 4).identity(),
        material: Material(T) = Material(T).new(),

        pub fn new() Self {
            const static = struct {
                var id: usize = 0;
            };

            const save = static.id;
            static.id += 1;

            return .{ .id = save };
        }

        pub fn set_transform(self: *Self, matrix: Matrix(T, 4)) MatrixError!void {
            if (matrix.det() == 0.0) {
                return MatrixError.NotInvertible;
            }

            self.transform = matrix;
        }

        pub fn intersect(self: Self, allocator: Alloctor, ray: Ray(T)) !Intersections(T) {
            const ray_tr = ray.transform(self.transform.inverse() catch unreachable);
            const sphere_to_ray_tr = ray_tr.origin.sub(Tuple(T).new_point(0.0, 0.0, 0.0));

            const a = ray_tr.direction.dot(ray_tr.direction);
            const b = 2.0 * sphere_to_ray_tr.dot(ray_tr.direction);
            const c = sphere_to_ray_tr.dot(sphere_to_ray_tr) - 1.0;

            const discriminant = b * b - 4.0 * a * c;
            
            var xs = Intersections(T).new(allocator);
            if (discriminant >= 0.0) {
                const t1 = (-b - @sqrt(discriminant)) / (2.0 * a);
                const t2 = (-b + @sqrt(discriminant)) / (2.0 * a);

                try xs.add(.{ .t = t1, .object = self });
                try xs.add(.{ .t = t2, .object = self });
            }
            return xs;
        }

        pub fn normal_at(self: Self, world_point: Tuple(T)) Tuple(T) {
            const inv_transform = self.transform.inverse() catch unreachable;
            const object_point = inv_transform.tupleMul(world_point);
            const object_normal = object_point.sub(Tuple(T).new_point(0.0, 0.0, 0.0));
            var world_normal = inv_transform.transpose().tupleMul(object_normal);
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
        var it = xs.iterator();
        defer xs.destroy();

        try testing.expectEqual(xs.count(), 2);

        const first = it.next().?;
        const second = it.next().?;
        try testing.expectApproxEqAbs(first.t, 4.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 6.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).new_point(0.0, 1.0, -5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
        const s = Sphere(f32).new();
        var xs = try s.intersect(allocator, r);
        var it = xs.iterator();
        defer xs.destroy();

        try testing.expectEqual(xs.count(), 2);

        const first = it.next().?;
        const second = it.next().?;
        try testing.expectApproxEqAbs(first.t, 5.0, tolerance);
        try testing.expectApproxEqAbs(second.t, 5.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).new_point(0.0, 2.0, -5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
        const s = Sphere(f32).new();
        var xs = try s.intersect(allocator, r);
        defer xs.destroy();

        try testing.expectEqual(xs.count(), 0);
    }

    {
        const r = Ray(f32).new(Tuple(f32).new_point(0.0, 0.0, 0.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
        const s = Sphere(f32).new();
        var xs = try s.intersect(allocator, r);
        var it = xs.iterator();
        defer xs.destroy();

        try testing.expectEqual(xs.count(), 2);

        const first = it.next().?;
        const second = it.next().?;
        try testing.expectApproxEqAbs(first.t, 1.0, tolerance);
        try testing.expectApproxEqAbs(second.t, -1.0, tolerance);
        try testing.expectEqual(first.object, s);
        try testing.expectEqual(second.object, s);
    }

    {
        const r = Ray(f32).new(Tuple(f32).new_point(0.0, 0.0, 5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
        const s = Sphere(f32).new();
        var xs = try s.intersect(allocator, r);
        var it = xs.iterator();
        defer xs.destroy();

        try testing.expectEqual(xs.count(), 2);

        const first = it.next().?;
        const second = it.next().?;
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
        var it = xs.iterator();
        defer xs.destroy();

        try testing.expectEqual(xs.count(), 2);

        const first = it.next().?;
        const second = it.next().?;
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
        defer xs.destroy();

        try testing.expectEqual(xs.count(), 0);
    }
}

test "Hit" {
    const allocator = std.testing.allocator;

    {
        var s = Sphere(f32).new();
        var xs = Intersections(f32).new(allocator);
        defer xs.destroy();
        try xs.add(.{ .t = 1.0, .object = s});
        try xs.add(.{ .t = 2.0, .object = s});

        try testing.expectEqual(xs.hit(), .{ .t = 1.0, .object = s});
    }

    {
        var s = Sphere(f32).new();
        var xs = Intersections(f32).new(allocator);
        defer xs.destroy();
        try xs.add(.{ .t = -1.0, .object = s});
        try xs.add(.{ .t = 1.0, .object = s});

        try testing.expectEqual(xs.hit(), .{ .t = 1.0, .object = s});
    }

    {
        var s = Sphere(f32).new();
        var xs = Intersections(f32).new(allocator);
        defer xs.destroy();
        try xs.add(.{ .t = -2.0, .object = s});
        try xs.add(.{ .t = -1.0, .object = s});

        try testing.expectEqual(xs.hit(), null);
    }

    {
        var s = Sphere(f32).new();
        var xs = Intersections(f32).new(allocator);
        defer xs.destroy();
        try xs.add(.{ .t = 5.0, .object = s});
        try xs.add(.{ .t = 7.0, .object = s});
        try xs.add(.{ .t = -3.0, .object = s});
        try xs.add(.{ .t = 2.0, .object = s});

        try testing.expectEqual(xs.hit(), .{ .t = 2.0, .object = s});
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
