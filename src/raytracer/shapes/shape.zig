const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Material = @import("../material.zig").Material;
const Ray = @import("../ray.zig").Ray;
const Sphere = @import("sphere.zig").Sphere;
const Cube = @import("cube.zig").Cube;
const Plane = @import("plane.zig").Plane;
const PreComputations = @import("../world.zig").PreComputations;

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

            return std.sort.asc(T)({}, a.t, b.t);
        }
    };
}

pub fn Intersections(comptime T: type) type {
    return ArrayList(Intersection(T));
}


pub fn sortIntersections(comptime T: type, intersections: []Intersection(T)) void {
    std.sort.sort(Intersection(T), intersections, {}, IntersectionCmp(T).call);
}

/// Finds the first intersection in `intersection` with a nonnegative `t`.
///
/// Assumes `intersections` is sorted.
pub fn hit(comptime T: type, intersections: []Intersection(T)) ?usize {
    // Could use binary search here ...
    var i: usize = 0;
    while (i < intersections.len) : (i += 1) {
        if (intersections[i].t >= 0.0) {
            return i;
        }
    }

    return null;
}

/// A `Shape` is an object in a world, backed by floats of type `T`.
pub fn Shape(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The various concrete shapes. Structs that can be placed in
        /// this tagged union must provide the following functions:
        /// 
        /// fn localIntersect(self: Self, allocator: Allocator, super: Shape(T), ray: Ray(T)) !Intersections(T);
        /// fn localNormalAt(self: Self, super: Shape(T), point: Tuple(T)) Tuple(T);
        ///
        /// `localIntersect` should compute the intersections with the shape for the given `ray`.
        /// `localNormalAt` should return the surface normal vector at the point in object space `point`.
        const Variant = union(enum) {
            test_shape: TestShape(T),
            sphere: Sphere(T),
            cube: Cube(T),
            plane: Plane(T),
        };

        id: usize,
        _transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        _inverse_transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        _inverse_transform_transpose: Matrix(T, 4) = Matrix(T, 4).identity(),
        material: Material(T) = Material(T).new(),
        _saved_ray: ?Ray(T) = null,
        variant: Variant,
        casts_shadow: bool = true,

        /// Creates a new `Shape`.
        fn new(variant: Variant) Self {
            const static = struct {
                var id: usize = 0;
            };

            const save = static.id;
            static.id += 1;

            return .{ .id = save, .variant = variant };
        }

        /// Creates a new test shape.
        fn testShape() Self {
            return Self.new(Self.Variant { .test_shape = TestShape(T).new() });
        }

        /// Creates a new sphere.
        pub fn sphere() Self {
            return Self.new(Self.Variant { .sphere = Sphere(T) {} });
        }

        /// Creates a glass sphere.
        pub fn glass_sphere() Self {
            var sphere_ = Self.sphere();
            sphere_.material.transparency = 1.0;
            sphere_.material.refractive_index = 1.5;
            return sphere_;
        }

        /// Creates a new cube.
        pub fn cube() Self {
            return Self.new(Self.Variant { .cube = Cube(T) {} });
        }

        /// Creates a new plane.
        pub fn plane() Self {
            return Self.new(Self.Variant { .plane = Plane(T) {} });
        }

        /// Sets the shape's transformation matrix to `matrix`.
        ///
        /// Fails if `matrix` is not invertible.
        pub fn setTransform(self: *Self, matrix: Matrix(T, 4)) !void {
            self._transform = matrix;
            self._inverse_transform = try matrix.inverse();
            self._inverse_transform_transpose = self._inverse_transform.transpose();
        }

        /// Finds the intersections of `ray` with `self`.
        pub fn intersect(self: *Self, allocator: Allocator, ray: Ray(T)) !Intersections(T) {
            self._saved_ray = ray.transform(self._inverse_transform);

            // At this point we need to call the variant's implementation of
            // `localIntersect`. The normal way to do this is with `inline else` in
            // a switch statement. But that way is unfortunately just broken; the
            // compiler will randomly lose its fucking mind and optimize out the
            // entire switch in release mode. Instead, we have to use this monstronsity
            // here and elsewhere.
            // TODO: check if `inline else` works in future versions of Zig.
            const Tag = @typeInfo(@TypeOf(self.variant)).Union.tag_type.?;
            inline for (@typeInfo(Tag).Enum.fields) |field| {
                if (field.value == @enumToInt(self.variant)) {
                    return @field(self.variant, field.name).localIntersect(allocator, self.*, self._saved_ray.?);
                }
            }

            unreachable;
        }

        /// Finds the surface normal vector at the `point` in world space.
        pub fn normalAt(self: Self, point: Tuple(T)) Tuple(T) {
            const local_point = self._inverse_transform.tupleMul(point);
            const Tag = @typeInfo(@TypeOf(self.variant)).Union.tag_type.?;
            inline for (@typeInfo(Tag).Enum.fields) |field| {
                if (field.value == @enumToInt(self.variant)) {
                    const local_normal = @field(self.variant, field.name).localNormalAt(self, local_point);
                    var world_normal = self._inverse_transform_transpose.tupleMul(local_normal);
                    world_normal.w = 0.0;
                    return world_normal.normalized();
                }
            }

            unreachable;
        }
    };
}

/// A simple shape for testing.
fn TestShape(comptime T: type) type {
    return struct {
        const Self = @This();

        fn new() Self {
            return .{};
        }

        fn localIntersect(self: Self, allocator: Allocator, super: Shape(T), ray: Ray(T)) !Intersections(T) {
            _ = self;
            _ = super;
            _ = ray;
            return Intersections(T).init(allocator);
        }

        fn localNormalAt(self: Self, super: Shape(T), point: Tuple(T)) Tuple(T) {
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
        sortIntersections(f32, xs.items);

        try testing.expectEqual(xs.items[hit(f32, xs.items).?], .{ .t = 1.0, .object = s});
    }

    {
        var s = Shape(f32).sphere();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = -1.0, .object = s});
        try xs.append(.{ .t = 1.0, .object = s});
        sortIntersections(f32, xs.items);

        try testing.expectEqual(xs.items[hit(f32, xs.items).?], .{ .t = 1.0, .object = s});
    }

    {
        var s = Shape(f32).sphere();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = -2.0, .object = s});
        try xs.append(.{ .t = -1.0, .object = s});
        sortIntersections(f32, xs.items);

        try testing.expectEqual(hit(f32, xs.items), null);
    }

    {
        var s = Shape(f32).sphere();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(.{ .t = 5.0, .object = s});
        try xs.append(.{ .t = 7.0, .object = s});
        try xs.append(.{ .t = -3.0, .object = s});
        try xs.append(.{ .t = 2.0, .object = s});
        sortIntersections(f32, xs.items);

        try testing.expectEqual(xs.items[hit(f32, xs.items).?], .{ .t = 2.0, .object = s});
    }
}

fn testRefraction(comptime T: type, allocator: Allocator, i: usize, n1: T, n2: T) !void {
    var a = Shape(T).glass_sphere();
    try a.setTransform(Matrix(T, 4).identity().scale(2.0, 2.0, 2.0));
    a.material.refractive_index = 1.5;

    var b = Shape(T).glass_sphere();
    try b.setTransform(Matrix(T, 4).identity().translate(0.0, 0.0, -0.25));
    b.material.refractive_index = 2.0;

    var c = Shape(T).glass_sphere();
    try c.setTransform(Matrix(T, 4).identity().translate(0.0, 0.0, 0.25));
    c.material.refractive_index = 2.5;

    const r = Ray(T).new(Tuple(T).point(0.0, 0.0, -4.0), Tuple(T).vec3(0.0, 0.0, 1.0));
    var xs = Intersections(T).init(allocator);
    defer xs.deinit();
    try xs.append(Intersection(T).new(2.0, a));
    try xs.append(Intersection(T).new(2.75, b));
    try xs.append(Intersection(T).new(3.25, c));
    try xs.append(Intersection(T).new(4.75, b));
    try xs.append(Intersection(T).new(5.25, c));
    try xs.append(Intersection(T).new(6.0, a));

    const comps = try PreComputations(T).new(allocator, xs.items[i], r, xs);

    try testing.expectEqual(comps.n1, n1);
    try testing.expectEqual(comps.n2, n2);
}

test "Refraction" {
    const allocator = testing.allocator;

    try testRefraction(f32, allocator, 0, 1.0, 1.5);
    try testRefraction(f32, allocator, 1, 1.5, 2.0);
    try testRefraction(f32, allocator, 2, 2.0, 2.5);
    try testRefraction(f32, allocator, 3, 2.5, 2.5);
    try testRefraction(f32, allocator, 4, 2.5, 1.5);
    try testRefraction(f32, allocator, 5, 1.5, 1.0);
}
