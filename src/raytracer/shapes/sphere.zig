const std = @import("std");
const testing = std.testing;
const Alloctor = std.mem.Allocator;
const PriorityQueue = std.PriorityQueue;

const Tuple = @import("../tuple.zig").Tuple;
const Ray = @import("../ray.zig").Ray;

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
        _: T = 0,

        pub fn new() Self {
            const static = struct {
                var id: usize = 0;
            };

            const save = static.id;
            static.id += 1;

            return .{ .id = save };
        }

        pub fn intersect(self: Self, allocator: Alloctor, ray: Ray(T)) !Intersections(T) {
            const sphere_to_ray = ray.origin.sub(Tuple(T).new_point(0.0, 0.0, 0.0));

            const a = ray.direction.dot(ray.direction);
            const b = 2.0 * sphere_to_ray.dot(ray.direction);
            const c = sphere_to_ray.dot(sphere_to_ray) - 1.0;

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

    var r = Ray(f32).new(Tuple(f32).new_point(0.0, 0.0, -5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
    var s = Sphere(f32).new();
    var xs1 = try s.intersect(allocator, r);
    var it = xs1.iterator();
    defer xs1.destroy();

    try testing.expectEqual(xs1.count(), 2);

    var first = it.next().?;
    var second = it.next().?;
    try testing.expectApproxEqAbs(first.t, 4.0, tolerance);
    try testing.expectApproxEqAbs(second.t, 6.0, tolerance);
    try testing.expectEqual(first.object, s);
    try testing.expectEqual(second.object, s);

    r = Ray(f32).new(Tuple(f32).new_point(0.0, 1.0, -5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
    s = Sphere(f32).new();
    var xs2 = try s.intersect(allocator, r);
    it = xs2.iterator();
    defer xs2.destroy();

    try testing.expectEqual(xs2.count(), 2);

    first = it.next().?;
    second = it.next().?;
    try testing.expectApproxEqAbs(first.t, 5.0, tolerance);
    try testing.expectApproxEqAbs(second.t, 5.0, tolerance);
    try testing.expectEqual(first.object, s);
    try testing.expectEqual(second.object, s);

    r = Ray(f32).new(Tuple(f32).new_point(0.0, 2.0, -5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
    s = Sphere(f32).new();
    var xs3 = try s.intersect(allocator, r);
    defer xs3.destroy();

    try testing.expectEqual(xs3.count(), 0);

    r = Ray(f32).new(Tuple(f32).new_point(0.0, 0.0, 0.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
    s = Sphere(f32).new();
    var xs4 = try s.intersect(allocator, r);
    it = xs4.iterator();
    defer xs4.destroy();

    try testing.expectEqual(xs4.count(), 2);

    first = it.next().?;
    second = it.next().?;
    try testing.expectApproxEqAbs(first.t, 1.0, tolerance);
    try testing.expectApproxEqAbs(second.t, -1.0, tolerance);
    try testing.expectEqual(first.object, s);
    try testing.expectEqual(second.object, s);

    r = Ray(f32).new(Tuple(f32).new_point(0.0, 0.0, 5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
    s = Sphere(f32).new();
    var xs5 = try s.intersect(allocator, r);
    it = xs5.iterator();
    defer xs5.destroy();

    try testing.expectEqual(xs5.count(), 2);

    first = it.next().?;
    second = it.next().?;
    try testing.expectApproxEqAbs(first.t, -6.0, tolerance);
    try testing.expectApproxEqAbs(second.t, -4.0, tolerance);
    try testing.expectEqual(first.object, s);
    try testing.expectEqual(second.object, s);
}

test "Hit" {
    const allocator = std.testing.allocator;

    var s = Sphere(f32).new();
    var xs1 = Intersections(f32).new(allocator);
    defer xs1.destroy();
    try xs1.add(.{ .t = 1.0, .object = s});
    try xs1.add(.{ .t = 2.0, .object = s});

    try testing.expectEqual(xs1.hit(), .{ .t = 1.0, .object = s});

    s = Sphere(f32).new();
    var xs2 = Intersections(f32).new(allocator);
    defer xs2.destroy();
    try xs2.add(.{ .t = -1.0, .object = s});
    try xs2.add(.{ .t = 1.0, .object = s});

    try testing.expectEqual(xs2.hit(), .{ .t = 1.0, .object = s});

    s = Sphere(f32).new();
    var xs3 = Intersections(f32).new(allocator);
    defer xs3.destroy();
    try xs3.add(.{ .t = -2.0, .object = s});
    try xs3.add(.{ .t = -1.0, .object = s});

    try testing.expectEqual(xs3.hit(), null);

    s = Sphere(f32).new();
    var xs4 = Intersections(f32).new(allocator);
    defer xs4.destroy();
    try xs4.add(.{ .t = 5.0, .object = s});
    try xs4.add(.{ .t = 7.0, .object = s});
    try xs4.add(.{ .t = -3.0, .object = s});
    try xs4.add(.{ .t = 2.0, .object = s});

    try testing.expectEqual(xs4.hit(), .{ .t = 2.0, .object = s});
}
