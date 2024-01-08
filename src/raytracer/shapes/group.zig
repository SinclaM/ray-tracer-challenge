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

        allocator: Allocator,
        children: ArrayList(Shape(T)),
        _bbox: *Shape(T),

        pub fn destroy(self: Self) void {
            for (self.children.items) |child| {
                switch (child.variant) {
                    .group => |g| g.destroy(),
                    .csg => |csg| csg.destroy(),
                    else => {}
                }
            }

            self.children.deinit();

            self.allocator.destroy(self._bbox);
        }

        pub fn localIntersect(
            self: Self, allocator: Allocator, super: *const Shape(T), ray: Ray(T)
        ) anyerror!Intersections(T) {
            _ = super;

            var all = Intersections(T).init(allocator);

            const bbox_xs = try self._bbox.intersect(allocator, ray);
            defer bbox_xs.deinit();
            if (bbox_xs.items.len == 0) {
                return all;
            }

            for (self.children.items) |*child| {
                const xs: Intersections(T) = try child.intersect(allocator, ray);
                defer xs.deinit();

                try all.appendSlice(xs.items);
            }

            sortIntersections(T, all.items);

            return all;
        }

        pub fn localNormalAt(self: Self, point: Tuple(T), hit: Intersection(T)) Tuple(T) {
            _ = self;
            _ = point;
            _ = hit;

            // TODO: can this be a compile error with duck typing?

            @panic("`localNormalAt` not implemented for groups");
        }

        /// Adds `child` to a group.
        pub fn addChild(self: *Self, child: Shape(T)) !void {
            try self.children.append(child);
            self._bbox.variant.bounding_box.merge(child.parentSpaceBounds().variant.bounding_box);
        }


        pub fn bounds(self: Self) Shape(T) {
            return self._bbox.*;
        }

        pub fn partitionChildren(self: *Self, allocator: Allocator) ![2]ArrayList(Shape(T)) {
            var left = ArrayList(Shape(T)).init(allocator);
            var right = ArrayList(Shape(T)).init(allocator);
            var new_children = ArrayList(Shape(T)).init(allocator);

            const split = self._bbox.variant.bounding_box.split();
            const left_box = &split[0].variant.bounding_box;
            const right_box = &split[1].variant.bounding_box;

            for (self.children.items) |child| {
                if (left_box.containsBox(
                        child.parentSpaceBounds().variant.bounding_box
                    )
                ) {
                    try left.append(child);
                } else if (
                    right_box.containsBox(
                        child.parentSpaceBounds().variant.bounding_box
                    )
                ) {
                    try right.append(child);
                } else {
                    try new_children.append(child);
                }
            }

            self.children.deinit();
            self.children = new_children;

            return [_]ArrayList(Shape(T)) { left, right };
        }

        pub fn makeSubgroup(
            self: *Self, allocator: Allocator, super: *Shape(T), children: ArrayList(Shape(T))
        ) !void {
            _ = self;

            defer children.deinit();

            var subgroup = try Shape(T).group(allocator);

            // Make sure not to simple assign `children` to `subgroup.children`.
            // Children need to be added explicitly with `addChild` so that
            // the necessary side effects (i.e. updating the subgroup's bounding
            // box) can happen.
            for (children.items) |child| {
                try subgroup.variant.group.addChild(child);
            }

            try super.variant.group.addChild(subgroup);
        }
    };
}

test "Creating a new group" {
    const allocator = testing.allocator;

    const g = try Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    try testing.expectEqual(g._transform, Matrix(f32, 4).identity());
    try testing.expectEqual(g.variant.group.children.items.len, 0);
}

test "Adding a child to a group" {
    const allocator = testing.allocator;

    var g = try Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    const s = Shape(f32).testShape();

    try g.variant.group.addChild(s);

    try testing.expectEqual(g.variant.group.children.items.len, 1);
    try testing.expectEqual(g.variant.group.children.items[0], s);
}

test "Intersecting a ray with an empty group" {
    const allocator = testing.allocator;

    var g = try Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0));

    const xs = try g.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 0);
}

test "Intersecting a ray with an nonempty group" {
    const allocator = testing.allocator;

    var g = try Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    const s1 = Shape(f32).sphere();
    var s2 = Shape(f32).sphere();
    try s2.setTransform(Matrix(f32, 4).identity().translate(0.0, 0.0, -3.0));
    var s3 = Shape(f32).sphere();
    try s3.setTransform(Matrix(f32, 4).identity().translate(5.0, 0.0, 0.0));

    try g.variant.group.addChild(s1);
    try g.variant.group.addChild(s2);
    try g.variant.group.addChild(s3);

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

    var g = try Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    var s = Shape(f32).sphere();
    try s.setTransform(Matrix(f32, 4).identity().translate(5.0, 0.0, 0.0));

    try g.variant.group.addChild(s);
    try g.setTransform(Matrix(f32, 4).identity().scale(2.0, 2.0, 2.0));

    const r = Ray(f32).new(Tuple(f32).point(10.0, 0.0, -10.0), Tuple(f32).vec3(0.0, 0.0, 1.0));

    const xs = try g.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 2);
}

test "A group has a bounding box that contains its children" {
    const allocator = testing.allocator;

    var s = Shape(f32).sphere();
    try s.setTransform(Matrix(f32, 4).identity().scale(2.0, 2.0, 2.0).translate(2.0, 5.0, -3.0));

    var c = Shape(f32).cylinder();
    c.variant.cylinder.min = -2.0;
    c.variant.cylinder.max = 2.0;
    try c.setTransform(Matrix(f32, 4).identity().scale(0.5, 1.0, 0.5).translate(-4.0, -1.0, 4.0));

    var g = try Shape(f32).group(allocator);
    defer g.variant.group.destroy();
    try g.variant.group.addChild(s);
    try g.variant.group.addChild(c);

    const box = g.bounds();

    try testing.expect(box.variant.bounding_box.min.approxEqual(Tuple(f32).point(-4.5, -3.0, -5.0)));

}

test "Partitioning a group's children" {
    const allocator = testing.allocator;

    var s1 = Shape(f32).sphere();
    try s1.setTransform(Matrix(f32, 4).identity().translate(-2.0, 0.0, 0.0));

    var s2 = Shape(f32).sphere();
    try s2.setTransform(Matrix(f32, 4).identity().translate(2.0, 0.0, 0.0));

    const s3 = Shape(f32).sphere();

    var g = try Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    try g.variant.group.addChild(s1);
    try g.variant.group.addChild(s2);
    try g.variant.group.addChild(s3);

    const partition = try g.variant.group.partitionChildren(allocator);
    defer {
        partition[0].deinit();
        partition[1].deinit();
    }

    const left = &partition[0];
    const right = &partition[1];

    try testing.expectEqualSlices(Shape(f32), g.variant.group.children.items, &[_]Shape(f32) { s3 });
    try testing.expectEqualSlices(Shape(f32), left.items, &[_]Shape(f32) { s1 });
    try testing.expectEqualSlices(Shape(f32), right.items, &[_]Shape(f32) { s2 });
}

test "Creating a sub-group from a list of children" {
    const allocator = testing.allocator;

    const s1 = Shape(f32).sphere();
    const s2 = Shape(f32).sphere();

    var g = try Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    var children = ArrayList(Shape(f32)).init(allocator);
    try children.append(s1);
    try children.append(s2);

    try g.variant.group.makeSubgroup(allocator, &g, children);

    try testing.expectEqual(g.variant.group.children.items.len, 1);
}

test "Subdividing a group partitions its children" {
    const allocator = testing.allocator;

    var s1 = Shape(f32).sphere();
    try s1.setTransform(Matrix(f32, 4).identity().translate(-2.0, -2.0, 0.0));

    var s2 = Shape(f32).sphere();
    try s2.setTransform(Matrix(f32, 4).identity().translate(-2.0, 2.0, 0.0));

    var s3 = Shape(f32).sphere();
    try s3.setTransform(Matrix(f32, 4).identity().scale(4.0, 4.0, 4.0));

    var g = try Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    try g.variant.group.addChild(s1);
    try g.variant.group.addChild(s2);
    try g.variant.group.addChild(s3);

    try g.divide(allocator, 1);

    try testing.expectEqual(g.variant.group.children.items[0], s3);

    const subgroup = &g.variant.group.children.items[1].variant.group;

    try testing.expectEqual(subgroup.children.items.len, 2);

    try testing.expectEqualSlices(
        Shape(f32),
        subgroup.children.items[0].variant.group.children.items,
        &[_]Shape(f32) { s1 }
    );

    try testing.expectEqualSlices(
        Shape(f32),
        subgroup.children.items[1].variant.group.children.items,
        &[_]Shape(f32) { s2 }
    );
}

test "Subdividing a group with too few children" {
    const allocator = testing.allocator;

    var s1 = Shape(f32).sphere();
    try s1.setTransform(Matrix(f32, 4).identity().translate(-2.0, 0.0, 0.0));

    var s2 = Shape(f32).sphere();
    try s2.setTransform(Matrix(f32, 4).identity().translate(2.0, 1.0, 0.0));

    var s3 = Shape(f32).sphere();
    try s3.setTransform(Matrix(f32, 4).identity().translate(2.0, -1.0, 0.0));

    const s4 = Shape(f32).sphere();

    var subgroup = try Shape(f32).group(allocator);
    try subgroup.variant.group.addChild(s1);
    try subgroup.variant.group.addChild(s2);
    try subgroup.variant.group.addChild(s3);

    var g = try Shape(f32).group(allocator);
    defer g.variant.group.destroy();

    try g.variant.group.addChild(subgroup);
    try g.variant.group.addChild(s4);

    try g.divide(allocator, 3);

    try testing.expectEqual(g.variant.group.children.items.len, 2);
    try testing.expectEqual(g.variant.group.children.items[0].variant.group.children.items.len, 2);

    try testing.expectEqualSlices(
        Shape(f32),
        g.variant.group.children.items[0].variant.group.children.items[0].variant.group.children.items,
        &[_]Shape(f32) { s1 }
    );

    try testing.expectEqualSlices(
        Shape(f32),
        g.variant.group.children.items[0].variant.group.children.items[1].variant.group.children.items,
        &[_]Shape(f32) { s2, s3 }
    );

    try testing.expectEqual(g.variant.group.children.items[1], s4);
}
