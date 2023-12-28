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
const BoundingBox = @import("bounding_box.zig").BoundingBox;
const Cylinder = @import("cylinder.zig").Cylinder;
const Cone = @import("cone.zig").Cone;
const Triangle = @import("triangle.zig").Triangle;
const SmoothTriangle = @import("triangle.zig").SmoothTriangle;
const Plane = @import("plane.zig").Plane;
const Group = @import("group.zig").Group;
const PreComputations = @import("../world.zig").PreComputations;

pub fn Intersection(comptime T: type) type {
    return struct {
        const Self = @This();
        t: T,
        object: *const Shape(T),
        // There is no significance in u and v defaulting to 0.0. They could
        // just as well default to `undefined`, but that would make checking
        // equality between intersections a little more tedious in tests.
        u: T = 0.0,
        v: T = 0.0,

        pub fn new(t: T, object: *const Shape(T)) Self {
            return .{ .t = t, .object = object };
        }

        pub fn uvNew(t: T, object: *const Shape(T), u: T, v: T) Self {
            return .{
                .t = t,
                .object = object,
                .u = u,
                .v = v
            };
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
    std.mem.sort(Intersection(T), intersections, {}, IntersectionCmp(T).call);
}

/// Finds the first intersection in `intersection` with a nonnegative `t`.
///
/// Assumes `intersections` is sorted.
pub fn hit(comptime T: type, intersections: []const Intersection(T)) ?usize {
    // Could use binary search here ...
    for (intersections, 0..) |intersection, i| {
        if (intersection.t >= 0.0) {
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
        /// fn localIntersect(
        ///     self: Self, allocator: Allocator, super: *const Shape(T), ray: Ray(T)
        /// ) !Intersections(T);
        /// fn localNormalAt(self: Self, point: Tuple(T), hit: Intersection(T)) Tuple(T);
        /// fn bounds(self: Self) Shape(T);
        ///
        /// `localIntersect` should compute the intersections with the shape for the given `ray`.
        /// `localNormalAt` should return the surface normal vector at the point in object space `point`.
        /// `bounds` should return a bounding box for `self` in object space.
        const Variant = union(enum) {
            test_shape: TestShape(T),
            sphere: Sphere(T),
            cube: Cube(T),
            bounding_box: BoundingBox(T),
            cylinder: Cylinder(T),
            cone: Cone(T),
            plane: Plane(T),
            triangle: Triangle(T),
            smooth_triangle: SmoothTriangle(T),
            group: Group(T),
        };

        id: usize,
        _transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        _inverse_transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        _inverse_transform_transpose: Matrix(T, 4) = Matrix(T, 4).identity(),
        material: Material(T) = Material(T).new(),
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

        pub fn worldToObject(self: *const Self, point: Tuple(T)) Tuple(T) {
            const p = point;
        
            return self._inverse_transform.tupleMul(p);
        }

        pub fn normalToWorld(self: Self, normal: Tuple(T)) Tuple(T) {
            var n = self._inverse_transform_transpose.tupleMul(normal);
            n.w = 0.0;
            n = n.normalized();

            return n;
        }

        /// Creates a new test shape.
        pub fn testShape() Self {
            return Self.new(Self.Variant { .test_shape = TestShape(T).new() });
        }

        /// Creates a new sphere.
        pub fn sphere() Self {
            return Self.new(Self.Variant { .sphere = .{} });
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
            return Self.new(Self.Variant { .cube = .{} });
        }

        /// Creates a new bounding box.
        pub fn boundingBox() Self {
            return Self.new(Self.Variant { .bounding_box = .{} });
        }

        /// Creates a new cylinder.
        pub fn cylinder() Self {
            return Self.new(Self.Variant { .cylinder = .{} });
        }

        /// Creates a new cone.
        pub fn cone() Self {
            return Self.new(Self.Variant { .cone = .{} });
        }

        /// Creates a new triangle.
        pub fn triangle(p1: Tuple(T), p2: Tuple(T), p3: Tuple(T)) Self {
            const e1 = p2.sub(p1);
            const e2 = p3.sub(p1);

            const normal = e2.cross(e1).normalized();

            return Self.new(
                Self.Variant {
                    .triangle = .{
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                        .e1 = e1,
                        .e2 = e2,
                        .normal = normal
                    }
                }
            );
        }

        /// Creates a new smooth triangle.
        pub fn smoothTriangle(
            p1: Tuple(T), p2: Tuple(T), p3: Tuple(T), n1: Tuple(T), n2: Tuple(T), n3: Tuple(T)
        ) Self {
            const e1 = p2.sub(p1);
            const e2 = p3.sub(p1);

            return Self.new(
                Self.Variant {
                    .smooth_triangle = .{
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                        .e1 = e1,
                        .e2 = e2,
                        .n1 = n1,
                        .n2 = n2,
                        .n3 = n3,
                    }
                }
            );
        }

        /// Creates a new plane.
        pub fn plane() Self {
            return Self.new(Self.Variant { .plane = .{} });
        }

        /// Creates a new group.
        pub fn group(allocator: Allocator) !Self {
            const children = ArrayList(Shape(T)).init(allocator);

            const bbox = try allocator.create(Shape(T));
            bbox.* = Shape(T).boundingBox();

            return Self.new(
                Self.Variant {
                    .group = .{
                        .allocator = allocator, 
                        ._bbox = bbox,
                        .children = children
                    }
                }
            );
        }

        /// Adds `child` to a group.
        ///
        /// Assumes `self.variant` is a group.
        pub fn addChild(self: *Self, child: Self) !void {
            try self.variant.group.children.append(child);
            self.variant.group._bbox.variant.bounding_box
                .merge(child.parent_space_bounds().variant.bounding_box);
        }

        /// Sets the shape's transformation matrix to `matrix`.
        ///
        /// Fails if `matrix` is not invertible.
        pub fn setTransform(self: *Self, matrix: Matrix(T, 4)) !void {
            switch (self.variant) {
                .group => |*g| {
                    // Groups pass on the transformation to their children.
                    for (g.children.items) |*child| {
                        try child.setTransform(matrix.mul(child._transform));
                    }

                    // And they update their bounding boxes too.
                    g._bbox.* = g._bbox.variant.bounding_box.transform(matrix);
                    
                },
                else => {
                    // Everyone else updates their own state.
                    self._transform = matrix;
                    self._inverse_transform = try matrix.inverse();
                    self._inverse_transform_transpose = self._inverse_transform.transpose();
                }
            }
        }

        /// Finds the intersections of `ray` with `self`.
        pub fn intersect(self: *const Self, allocator: Allocator, ray: Ray(T)) !Intersections(T) {
            const transformed = switch (self.variant) {
                .group => ray,
                else => ray.transform(self._inverse_transform)
            };

            // At this point we need to call the variant's implementation of
            // `localIntersect`. The normal way to do this is with `inline else` in
            // a switch statement. But that way is unfortunately just broken; the
            // compiler will randomly lose its fucking mind and optimize out the
            // entire switch in release mode. Instead, we have to use this monstronsity
            // here and elsewhere.
            // TODO: check if `inline else` works in future versions of Zig.
            const Tag = @typeInfo(@TypeOf(self.variant)).Union.tag_type.?;
            inline for (@typeInfo(Tag).Enum.fields) |field| {
                if (field.value == @intFromEnum(self.variant)) {
                    return @field(self.variant, field.name).localIntersect(allocator, self, transformed);
                }
            }

            unreachable;
        }

        /// Finds the surface normal vector at the `point` in world space.
        pub fn normalAt(self: Self, point: Tuple(T), hit_: Intersection(T)) Tuple(T) {
            const local_point = self.worldToObject(point);

            const Tag = @typeInfo(@TypeOf(self.variant)).Union.tag_type.?;
            inline for (@typeInfo(Tag).Enum.fields) |field| {
                if (field.value == @intFromEnum(self.variant)) {
                    const local_normal = @field(self.variant, field.name).localNormalAt(local_point, hit_);
                    return self.normalToWorld(local_normal);
                }
            }

            unreachable;
        }

        /// Finds the bounds of this shape in object space.
        pub fn bounds(self: Self) Self {
            const Tag = @typeInfo(@TypeOf(self.variant)).Union.tag_type.?;
            inline for (@typeInfo(Tag).Enum.fields) |field| {
                if (field.value == @intFromEnum(self.variant)) {
                    return @field(self.variant, field.name).bounds();
                }
            }

            unreachable;
        }

        pub fn parent_space_bounds(self: Self) Self {
            return self
                .bounds()
                .variant
                .bounding_box
                .transform(self._transform);
        }

        pub fn divide(self: *Self, allocator: Allocator, threshold: usize) !void {
            switch (self.variant) {
                .group => |*g| {
                    if (g.children.items.len >= threshold) {
                        const partition = try g.partition_children(allocator);
                        const left = partition[0];
                        const right = partition[1];

                        if (left.items.len > 0) {
                            try g.make_subgroup(allocator, self, left);
                        }

                        if (right.items.len > 0) {
                            try g.make_subgroup(allocator, self, right);
                        }
                    }

                    for (g.children.items) |*child| {
                        try child.divide(allocator, threshold);
                    }
                },
                else => {}
            }
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

        fn localIntersect(
            self: Self, allocator: Allocator, super: *const Shape(T), ray: Ray(T)
        ) !Intersections(T) {
            _ = self;
            _ = super;
            _ = ray;
            return Intersections(T).init(allocator);
        }

        fn localNormalAt(self: Self, point: Tuple(T), hit_: Intersection(T)) Tuple(T) {
            _ = self;
            _ = point;
            _ = hit_;

            return Tuple(T).point(0.0, 0.0, 0.0);
        }

        pub fn bounds(self: Self) Shape(T) {
            _ = self;

            var box = Shape(T).boundingBox();
            box.variant.bounding_box.min = Tuple(T).point(-1.0, -1.0, -1.0);
            box.variant.bounding_box.max = Tuple(T).point(1.0, 1.0, 1.0);

            return box;
        }
    };
}

test "Id uniqueness" {
    const s1 = Shape(f32).sphere();
    const s2 = Shape(f32).sphere();
    const s3 = Shape(f32).testShape();
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
        try xs.append(Intersection(f32).new(1.0, &s));
        try xs.append(Intersection(f32).new(2.0, &s));
        sortIntersections(f32, xs.items);

        try testing.expectEqual(
            xs.items[hit(f32, xs.items).?], Intersection(f32).new(1.0, &s)
        );
    }

    {
        var s = Shape(f32).sphere();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(Intersection(f32).new(-1.0, &s));
        try xs.append(Intersection(f32).new(1.0, &s));
        sortIntersections(f32, xs.items);

        try testing.expectEqual(
            xs.items[hit(f32, xs.items).?], Intersection(f32).new(1.0, &s)
        );
    }

    {
        var s = Shape(f32).sphere();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(Intersection(f32).new(-2.0, &s));
        try xs.append(Intersection(f32).new(-1.0, &s));
        sortIntersections(f32, xs.items);

        try testing.expectEqual(hit(f32, xs.items), null);
    }

    {
        var s = Shape(f32).sphere();
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(Intersection(f32).new(5.0, &s));
        try xs.append(Intersection(f32).new(7.0, &s));
        try xs.append(Intersection(f32).new(-3.0, &s));
        try xs.append(Intersection(f32).new(2.0, &s));
        sortIntersections(f32, xs.items);

        try testing.expectEqual(
            xs.items[hit(f32, xs.items).?], Intersection(f32).new(2.0, &s)
        );
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
    try xs.append(Intersection(T).new(2.0, &a));
    try xs.append(Intersection(T).new(2.75, &b));
    try xs.append(Intersection(T).new(3.25, &c));
    try xs.append(Intersection(T).new(4.75, &b));
    try xs.append(Intersection(T).new(5.25, &c));
    try xs.append(Intersection(T).new(6.0, &a));

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

test "Converting a point from world to object space" {
    const allocator = testing.allocator;

    var g1 = try Shape(f32).group(allocator);
    defer g1.variant.group.destroy();

    var g2 = try Shape(f32).group(allocator);

    var s = Shape(f32).sphere();
    try s.setTransform(Matrix(f32, 4).identity().translate(5.0, 0.0, 0.0));

    try g2.addChild(s);
    try g1.addChild(g2);

    try g2.setTransform(Matrix(f32, 4).identity().scale(2.0, 2.0, 2.0));
    try g1.setTransform(Matrix(f32, 4).identity().rotateY(std.math.pi / 2.0));

    const p = g1.variant.group.children.items[0]
                .variant.group.children.items[0]
                .worldToObject(Tuple(f32).point(-2.0, 0.0, -10.0));
    try testing.expect(p.approxEqual(Tuple(f32).point(0.0, 0.0, -1.0)));
}

test "Converting a normal from object to world space" {
    const allocator = testing.allocator;

    var g1 = try Shape(f32).group(allocator);
    defer g1.variant.group.destroy();

    var g2 = try Shape(f32).group(allocator);

    var s = Shape(f32).sphere();
    try s.setTransform(Matrix(f32, 4).identity().translate(5.0, 0.0, 0.0));

    try g2.addChild(s);
    try g1.addChild(g2);

    try g2.setTransform(Matrix(f32, 4).identity().scale(1.0, 2.0, 3.0));
    try g1.setTransform(Matrix(f32, 4).identity().rotateY(std.math.pi / 2.0));

    const n = g1.variant.group.children.items[0]
                .variant.group.children.items[0]
                .normalToWorld(Tuple(f32).vec3(1.0 / @sqrt(3.0), 1.0 / @sqrt(3.0), 1.0 / @sqrt(3.0)));

    try testing.expect(n.approxEqual(Tuple(f32).vec3(0.28571, 0.42857, -0.85714)));
}

test "Finding the normal on a child object" {
    const allocator = testing.allocator;

    var g1 = try Shape(f32).group(allocator);
    defer g1.variant.group.destroy();

    var g2 = try Shape(f32).group(allocator);

    var s = Shape(f32).sphere();
    try s.setTransform(Matrix(f32, 4).identity().translate(5.0, 0.0, 0.0));

    try g2.addChild(s);
    try g1.addChild(g2);

    try g2.setTransform(Matrix(f32, 4).identity().scale(1.0, 2.0, 3.0));
    try g1.setTransform(Matrix(f32, 4).identity().rotateY(std.math.pi / 2.0));

    const n = g1.variant.group.children.items[0]
                .variant.group.children.items[0]
                .normalAt(Tuple(f32).point(1.7321, 1.1547, -5.5774), undefined);

    try testing.expect(n.approxEqual(Tuple(f32).vec3(0.2857, 0.42854, -0.85716)));
}

test "A test shape has (arbitrary) bounds" {
    const s = Shape(f32).testShape();
    const box = s.bounds();

    try testing.expectEqual(box.variant.bounding_box.min, Tuple(f32).point(-1.0, -1.0, -1.0));
    try testing.expectEqual(box.variant.bounding_box.max, Tuple(f32).point(1.0, 1.0, 1.0));
}

test "Querying a shape's bounding box in its parent's space" {
    const allocator = testing.allocator;

    var s = Shape(f32).sphere();
    try s.setTransform(Matrix(f32, 4).identity().scale(0.5, 2.0, 4.0).translate(1.0, -3.0, 5.0));

    var g = try Shape(f32).group(allocator);
    defer g.variant.group.destroy();
    try g.addChild(s);
    try g.setTransform(Matrix(f32, 4).identity().shear(.{ .xz = 3.0, .zy = -2.2 }));

    const box = s.parent_space_bounds();

    try testing.expect(box.variant.bounding_box.min.approxEqual(Tuple(f32).point(0.5, -5.0, 1.0)));
    try testing.expect(box.variant.bounding_box.max.approxEqual(Tuple(f32).point(1.5, -1.0, 9.0)));
}
