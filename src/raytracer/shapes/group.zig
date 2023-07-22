const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Ray = @import("../ray.zig").Ray;

const shape = @import("shape.zig");
const Intersection = shape.Intersection;
const Intersections = shape.Intersections;
const sortIntersections = shape.sortIntersections;
const Shape = shape.Shape;

/// A group of objects, backed by floats of type `T`.
pub fn Group(comptime T: type) type {
    return struct {
        const Self = @This();

        children: ArrayList(Shape(T)),

        pub fn destroy(self: Self) void {
            for (self.children.items) |child| {
                switch (child.variant) {
                    .group => |g| g.destroy(),
                    else => {}
                }
            }

            self.children.deinit();
        }

        pub fn localIntersect(
            self: Self, allocator: Allocator, super: *const Shape(T), ray: Ray(T)
        ) anyerror!Intersections(T) {
            _ = super;

            var all = Intersections(T).init(allocator);

            for (self.children.items) |*child| {
                const xs: Intersections(T) = try child.intersect(allocator, ray);
                defer xs.deinit();

                try all.appendSlice(xs.items);
            }

            sortIntersections(T, all.items);

            return all;
        }

        pub fn localNormalAt(self: Self, super: Shape(T), point: Tuple(T)) Tuple(T) {
            _ = self;
            _ = super;
            _ = point;

            // TODO: can this be a compile error with duck typing?

            @panic("`localNormalAt` not implemented for groups");
        }
    };
}

test "Creating a new group" {
    const allocator = testing.allocator;

    const g = Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    try testing.expectEqual(g._transform, Matrix(f32, 4).identity());
    try testing.expectEqual(g.variant.group.children.items.len, 0);
}

test "Adding a child to a group" {
    const allocator = testing.allocator;

    var g = Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    var s = Shape(f32).testShape();

    try g.addChild(s);

    try testing.expectEqual(g.variant.group.children.items.len, 1);
    try testing.expectEqual(g.variant.group.children.items[0], s);
}

test "Intersecting a ray with an empty group" {
    const allocator = testing.allocator;

    var g = Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0));

    const xs = try g.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 0);
}

test "Intersecting a ray with an nonempty group" {
    const allocator = testing.allocator;

    var g = Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    var s1 = Shape(f32).sphere();
    var s2 = Shape(f32).sphere();
    try s2.setTransform(Matrix(f32, 4).identity().translate(0.0, 0.0, -3.0));
    var s3 = Shape(f32).sphere();
    try s3.setTransform(Matrix(f32, 4).identity().translate(5.0, 0.0, 0.0));

    try g.addChild(s1);
    try g.addChild(s2);
    try g.addChild(s3);

    const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));

    const xs = try g.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 4);

    try testing.expectEqual(xs.items[0].object, &g.variant.group.children.items[1]);
    try testing.expectEqual(xs.items[1].object, &g.variant.group.children.items[1]);
    try testing.expectEqual(xs.items[2].object, &g.variant.group.children.items[0]);
    try testing.expectEqual(xs.items[3].object, &g.variant.group.children.items[0]);
}

test "Intersecting a transformed group" {
    const allocator = testing.allocator;

    var g = Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    var s = Shape(f32).sphere();
    try s.setTransform(Matrix(f32, 4).identity().translate(5.0, 0.0, 0.0));

    try g.addChild(s);
    try g.setTransform(Matrix(f32, 4).identity().scale(2.0, 2.0, 2.0));

    const r = Ray(f32).new(Tuple(f32).point(10.0, 0.0, -10.0), Tuple(f32).vec3(0.0, 0.0, 1.0));

    const xs = try g.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 2);
}
