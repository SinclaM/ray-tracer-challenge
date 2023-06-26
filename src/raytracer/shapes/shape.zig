const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const pi = std.math.pi;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Ray = @import("../ray.zig").Ray;
const Material = @import("../material.zig").Material;
const global = @import("../globals.zig").global;

pub fn Intersection(comptime T: type) type {
    return struct {
        const Self = @This();
        t: T,
        object: Shape(T),

        pub fn new(t: T, object: Shape(T)) Self {
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

pub fn Aligned(comptime T: type) type {
    return *align(@alignOf(Shape(T))) anyopaque;
} 

pub fn Shape(comptime T: type) type {
    return extern struct {
        const Self = @This();
        const LocalIntersectFn = *const fn(Aligned(T), allocator: Allocator, ray: Ray(T)) anyerror!Intersections(T);
        const LocalNormalAtFn = *const fn(Aligned(T), Tuple(T)) Tuple(T);

        id: usize,
        material: Material(T) = Material(T).new(),
        _transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        _inverse_transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        _inverse_transform_transpose: Matrix(T, 4) = Matrix(T, 4).identity(),
        _saved_ray: Ray(T) = undefined,
        local_intersect: LocalIntersectFn,
        local_normal_at: LocalNormalAtFn,

        pub fn new(local_intersect: LocalIntersectFn, local_normal_at: LocalNormalAtFn) Self {
            const save = global.shape_id;
            global.shape_id += 1;

            return .{ .id = save, .local_intersect = local_intersect, .local_normal_at = local_normal_at };
        }

        pub fn setTransform(self: *Self, matrix: Matrix(T, 4)) !void {
            self._transform = matrix;
            self._inverse_transform = try matrix.inverse();
            self._inverse_transform_transpose = self._inverse_transform.transpose();
        }

        pub fn intersect(self: *Self, allocator: Allocator, ray: Ray(T)) !Intersections(T) {
            self._saved_ray = ray.transform(self._inverse_transform);
            return self.local_intersect(@ptrCast(Aligned(T), self), allocator, self._saved_ray);
        }

        pub fn normalAt(self: *Self, world_point: Tuple(T)) Tuple(T) {
            const inv_transform = self._inverse_transform;
            const object_point = inv_transform.tupleMul(world_point);
            const object_normal = self.local_normal_at(@ptrCast(Aligned(T), self), object_point);
            var world_normal = self._inverse_transform_transpose.tupleMul(object_normal);
            world_normal.w = 0.0;
            return world_normal.normalized();
        }
    };
}

pub fn TestShape(comptime T: type) type {
    return extern struct {
        const Self = @This();

        shape: Shape(T),

        pub fn new() Self {
            return .{ .shape = Shape(T).new(Self.localIntersect, Self.localNormalAt) };
        }

        pub fn localIntersect(self: Aligned(T), allocator: Allocator, ray: Ray(T)) !Intersections(T) {
            _ = self;
            _ = ray;
            return Intersections(T).init(allocator);
        }

        pub fn localNormalAt(self: Aligned(T), object_point: Tuple(T)) Tuple(T) {
            _ = self;
            return Tuple(T).vec3(object_point.x, object_point.y, object_point.z);
        }
    };
}

test "TestShape" {
    const allocator = testing.allocator;
    {
        var s = TestShape(f32).new();
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        try s.shape.setTransform(Matrix(f32, 4).identity().scale(2.0, 2.0, 2.0));
        const xs = try s.shape.intersect(allocator, r);
        defer xs.deinit();

        try testing.expect(s.shape._saved_ray.origin.approxEqual(Tuple(f32).point(0.0, 0.0, -2.5)));
        try testing.expect(s.shape._saved_ray.direction.approxEqual(Tuple(f32).vec3(0.0, 0.0, 0.5)));
    }

    {
        var s = TestShape(f32).new();
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        try s.shape.setTransform(Matrix(f32, 4).identity().translate(5.0, 0.0, 0.0));
        const xs = try s.shape.intersect(allocator, r);
        defer xs.deinit();

        try testing.expect(s.shape._saved_ray.origin.approxEqual(Tuple(f32).point(-5.0, 0.0, -5.0)));
        try testing.expect(s.shape._saved_ray.direction.approxEqual(Tuple(f32).vec3(0.0, 0.0, 1.0)));
    }

    {
        var s = TestShape(f32).new();
        try s.shape.setTransform(Matrix(f32, 4).identity().translate(0.0, 1.0, 0.0));
        try testing.expect(
            s.shape
                .normalAt(Tuple(f32).point(0, 1.70711, -0.70711))
                .approxEqual(Tuple(f32).vec3(0, 0.70711, -0.70711))
        );
    }

    {
        var s = TestShape(f32).new();
        try s.shape.setTransform(Matrix(f32, 4).identity().rotateZ(pi / 5.0).scale(1.0, 0.5, 1.0));
        try testing.expect(
            s.shape
                .normalAt(Tuple(f32).point(0, 1.0 / @sqrt(2.0), -1.0 / @sqrt(2.0)))
                .approxEqual(Tuple(f32).vec3(0, 0.97014, -0.24254))
        );
    }
}
