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

pub const Operation = enum {
    Union,
    Intersection,
    Difference,
};

/// A constructive solid geometry object, backed by floats of type `T`.
pub fn Csg(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        left: *Shape(T),
        right: *Shape(T),
        operation: Operation,
        _bbox: *Shape(T),

        pub fn destroy(self: Self) void {
            switch (self.left.variant) {
                .group => |g| g.destroy(),
                .csg => |csg| csg.destroy(),
                else => {}
            }

            switch (self.right.variant) {
                .group => |g| g.destroy(),
                .csg => |csg| csg.destroy(),
                else => {}
            }

            self.allocator.destroy(self.left);
            self.allocator.destroy(self.right);
            self.allocator.destroy(self._bbox);
        }

        fn filterIntersections(self: Self, xs: []Intersection(T)) !Intersections(T) {
            var inl = false;
            var inr = false;

            var result = Intersections(T).init(self.allocator);
            errdefer result.deinit();

            for (xs) |i| {
                const lhit = includes(T, self.left, i.object);

                if (intersectionAllowed(self.operation, lhit, inl, inr)) {
                    try result.append(i);
                }

                if (lhit) {
                    inl = !inl;
                } else {
                    inr = !inr;
                }
            }

            return result;
        }

        pub fn localIntersect(
            self: Self, allocator: Allocator, super: *const Shape(T), ray: Ray(T)
        ) anyerror!Intersections(T) {
            _ = super;

            const bbox_xs = try self._bbox.intersect(allocator, ray);
            defer bbox_xs.deinit();
            if (bbox_xs.items.len == 0) {
                return Intersections(T).init(allocator);
            }

            var xs = try self.left.intersect(allocator, ray);
            defer xs.deinit();

            const rightxs = try self.right.intersect(allocator, ray);
            defer rightxs.deinit();

            try xs.appendSlice(rightxs.items);

            sortIntersections(T, xs.items);
            return try self.filterIntersections(xs.items);
        }

        pub fn localNormalAt(self: Self, point: Tuple(T), hit: Intersection(T)) Tuple(T) {
            _ = self;
            _ = point;
            _ = hit;

            // TODO: can this be a compile error with duck typing?

            @panic("`localNormalAt` not implemented for CSG");
        }

        pub fn bounds(self: Self) Shape(T) {
            return self._bbox.*;
        }

    };
}

pub fn intersectionAllowed(operation: Operation, lhit: bool, inl: bool, inr: bool) bool {
    return switch (operation) {
        .Union => (lhit and !inr) or !(lhit or inl),
        .Intersection => (lhit and inr) or (!lhit and inl),
        .Difference => (lhit and !inr) or (!lhit and inl),
    };
}

fn includes(comptime T: type, a: *const Shape(T), b: *const Shape(T)) bool {
    switch (a.variant) {
        .group => |g| {
            for (g.children.items) |child| {
                if (includes(T, &child, b)) {
                    return true;
                }
            }
            return false;
        },
        .csg => |csg| {
            return includes(T, csg.left, b) or includes(T, csg.right, b);
        },
        else => {
            return a.id == b.id;
        }
    }
}


test "CSG is created with an operation and two shapes" {
    const allocator = testing.allocator;

    const s1 = Shape(f32).sphere();
    const s2 = Shape(f32).cube();

    const c = try Shape(f32).csg(allocator, s1, s2, .Union);
    defer c.variant.csg.destroy();

    try testing.expectEqual(c.variant.csg.left.*, s1);
    try testing.expectEqual(c.variant.csg.right.*, s2);
}

fn testIntersectionAllowed(op: Operation, lhit: bool, inl: bool, inr: bool, result: bool) !void {
    try testing.expectEqual(intersectionAllowed(op, lhit, inl, inr), result);
}

test "Evaluating the rule for a CSG operation" {
    try testIntersectionAllowed(.Union, true  , true  , true  , false);
    try testIntersectionAllowed(.Union, true  , true  , false , true);
    try testIntersectionAllowed(.Union, true  , false , true  , false);
    try testIntersectionAllowed(.Union, true  , false , false , true);
    try testIntersectionAllowed(.Union, false , true  , true  , false);
    try testIntersectionAllowed(.Union, false , true  , false , false);
    try testIntersectionAllowed(.Union, false , false , true  , true);
    try testIntersectionAllowed(.Union, false , false , false , true);
    
    try testIntersectionAllowed(.Intersection, true  , true  , true  , true);
    try testIntersectionAllowed(.Intersection, true  , true  , false , false);
    try testIntersectionAllowed(.Intersection, true  , false , true  , true);
    try testIntersectionAllowed(.Intersection, true  , false , false , false);
    try testIntersectionAllowed(.Intersection, false , true  , true  , true);
    try testIntersectionAllowed(.Intersection, false , true  , false , true);
    try testIntersectionAllowed(.Intersection, false , false , true  , false);
    try testIntersectionAllowed(.Intersection, false , false , false , false);

    try testIntersectionAllowed(.Difference, true  , true  , true  , false);
    try testIntersectionAllowed(.Difference, true  , true  , false , true);
    try testIntersectionAllowed(.Difference, true  , false , true  , false);
    try testIntersectionAllowed(.Difference, true  , false , false , true);
    try testIntersectionAllowed(.Difference, false , true  , true  , true);
    try testIntersectionAllowed(.Difference, false , true  , false , true);
    try testIntersectionAllowed(.Difference, false , false , true  , false);
    try testIntersectionAllowed(.Difference, false , false , false , false);
}

fn testFilterIntersections(
    comptime T: type, allocator: Allocator, operation: Operation, x0: usize, x1: usize
) !void {
    const s1 = Shape(T).sphere();
    const s2 = Shape(T).cube();

    const csg = try Shape(T).csg(allocator, s1, s2, operation);
    defer csg.variant.csg.destroy();

    var xs = Intersections(T).init(allocator);
    defer xs.deinit();

    try xs.append(Intersection(T).new(1.0, &s1));
    try xs.append(Intersection(T).new(2.0, &s2));
    try xs.append(Intersection(T).new(3.0, &s1));
    try xs.append(Intersection(T).new(4.0, &s2));

    const result = try csg.variant.csg.filterIntersections(xs.items);
    defer result.deinit();

    try testing.expectEqualSlices(
        Intersection(T), result.items, &[_]Intersection(T) { xs.items[x0], xs.items[x1] }
    );
}

test "Filtering a list of intersections" {
    const allocator = testing.allocator;

    try testFilterIntersections(f32, allocator, .Union, 0, 3);
    try testFilterIntersections(f32, allocator, .Intersection, 1, 2);
    try testFilterIntersections(f32, allocator, .Difference, 0, 1);
}


test "A ray misses a CSG object" {
    const allocator = testing.allocator;

    const csg = try Shape(f32).csg(allocator, Shape(f32).sphere(), Shape(f32).cube(), .Union);
    defer csg.variant.csg.destroy();

    const r = Ray(f32).new(Tuple(f32).point(0.0, 2.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));

    const xs = try csg.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 0);
}

test "A ray hits a CSG object" {
    const allocator = testing.allocator;

    const s1 = Shape(f32).sphere();

    var s2 = Shape(f32).sphere();
    try s2.setTransform(Matrix(f32, 4).identity().translate(0.0, 0.0, 0.5));

    const csg = try Shape(f32).csg(allocator, s1, s2, .Union);
    defer csg.variant.csg.destroy();

    const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));

    const xs = try csg.intersect(allocator, r);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 2);
    try testing.expectEqual(xs.items[0].t, 4.0);
    try testing.expectEqual(xs.items[0].object.id, s1.id);
    try testing.expectEqual(xs.items[1].t, 6.5);
    try testing.expectEqual(xs.items[1].object.id, s2.id);
}
