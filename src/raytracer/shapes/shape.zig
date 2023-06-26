const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Material = @import("../material.zig").Material;
const Ray = @import("../ray.zig").Ray;
const Sphere = @import("sphere.zig").Sphere;

const global = struct {
    var id: usize = 0;
};


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

pub fn Shape(comptime T: type) type {
    return struct {
        const Self = @This();

        const Variant = union(enum) {
            test_shape: TestShape(T),
            sphere: Sphere(T),
        };

        id: usize,
        _transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        _inverse_transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        _inverse_transform_transpose: Matrix(T, 4) = Matrix(T, 4).identity(),
        material: Material(T) = Material(T).new(),
        _saved_ray: ?Ray(T) = null,
        variant: Variant,

        fn new(variant: Variant) Self {
            const save = global.id;
            global.id += 1;

            return .{ .id = save, .variant = variant };
        }

        pub fn testShape() Self {
            return Shape(T).new(Shape(T).Variant { .test_shape = TestShape(T).new() });
        }

        pub fn sphere() Self {
            return Shape(T).new(Shape(T).Variant { .sphere = Sphere(T) {} });
        }

        pub fn setTransform(self: *Self, matrix: Matrix(T, 4)) !void {
            self._transform = matrix;
            self._inverse_transform = try matrix.inverse();
            self._inverse_transform_transpose = self._inverse_transform.transpose();
        }

        pub fn intersect(self: *Self, allocator: Allocator, ray: Ray(T)) !Intersections(T) {
            self._saved_ray = ray.transform(self._inverse_transform);
            switch (self.variant) {
                inline else => |s| { return s.localIntersect(allocator, self.*, self._saved_ray.?); },
            }
        }

        pub fn normalAt(self: Self, point: Tuple(T)) Tuple(T) {
            const local_point = self._inverse_transform.tupleMul(point);
            // Be very careful with this switch statement. If you try to assign to
            // local_normal with a switch expression instead of jamming the rest of the
            // function in the inline else, the compiler will lose its fucking mind and
            // optimize out the entire switch in release mode.
            switch (self.variant) {
                inline else => |s| {
                    const local_normal = s.localNormalAt(self, local_point);
                    var world_normal = self._inverse_transform_transpose.tupleMul(local_normal);
                    world_normal.w = 0.0;
                    return world_normal.normalized();
                },
            }

        }
    };
}

fn TestShape(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn new() Self {
            return .{};
        }

        pub fn localIntersect(self: Self, allocator: Allocator, super: Shape(T), ray: Ray(T)) !Intersections(T) {
            _ = self;
            _ = super;
            _ = ray;
            return Intersections(T).init(allocator);
        }

        pub fn localNormalAt(self: Self, super: Shape(T), point: Tuple(T)) Tuple(T) {
            _ = self;
            _ = super;
            _ = point;
            return Tuple(T).point(0.0, 0.0, 0.0);
        }
    };
}

test "Id uniqueness" {
    var s1 = Shape(f32).sphere();
    var s2 = Shape(f32).sphere();
    var s3 = Shape(f32).testShape();
    try testing.expect(s1.id != s2.id);
    try testing.expect(s2.id != s3.id);
    try testing.expect(s3.id != s1.id);
}

test "Creation" {
    var s = Shape(f32).testShape();
    try testing.expect(s._transform.approxEqual(Matrix(f32, 4).identity()));

    s = Shape(f32).testShape();
    try s.setTransform(Matrix(f32, 4).identity().translate(2.0, 3.0, 4.0));
    try testing.expect(
        s._transform.approxEqual(Matrix(f32, 4).identity().translate(2.0, 3.0, 4.0))
    );
    try testing.expect(
        s._inverse_transform.approxEqual(Matrix(f32, 4).identity().translate(-2.0, -3.0, -4.0))
    );
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

