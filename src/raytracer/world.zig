const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Tuple = @import("tuple.zig").Tuple;
const Matrix = @import("matrix.zig").Matrix;
const Ray = @import("ray.zig").Ray;
const Color = @import("color.zig").Color;
const Light = @import("light.zig").Light;
const Intersections = @import("shapes/sphere.zig").Intersections;
const sortIntersections = @import("shapes/sphere.zig").sortIntersections;
const Sphere = @import("shapes/sphere.zig").Sphere;

pub fn World(comptime T: type) type {
    return struct {
        const Self = @This();

        objects: ArrayList(Sphere(T)),
        lights: ArrayList(Light(T)),

        pub fn new(allocator: Allocator) Self {
            return .{ 
                .objects = ArrayList(Sphere(T)).init(allocator),
                .lights = ArrayList(Light(T)).init(allocator)
            };
        }

        pub fn default(allocator: Allocator) !Self {
            var world = Self.new(allocator);

            var sphere1 = Sphere(T).new();
            sphere1.material.color = Color(T).new(0.8, 1.0, 0.6);
            sphere1.material.diffuse = 0.7;
            sphere1.material.specular = 0.2;

            var sphere2 = Sphere(T).new();
            sphere2.set_transform(Matrix(T, 4).identity().scale(0.5, 0.5, 0.5)) catch unreachable;

            try world.objects.append(sphere1);
            try world.objects.append(sphere2);

            var light = Light(T).point_light(
                Tuple(T).new_point(-10.0, 10.0, -10.0),
                Color(T).new(1.0, 1.0, 1.0)
            );

            try world.lights.append(light);

            return world;
        }

        pub fn destroy(self: Self) void {
            self.objects.deinit();
            self.lights.deinit();
        }
        
        pub fn intersect(self: *Self, allocator: Allocator, ray: Ray(T)) !Intersections(T) {
            var all = Intersections(T).init(allocator);

            for (self.objects.items) |object| {
                var xs: Intersections(T) = try object.intersect(allocator, ray);
                defer xs.deinit();

                try all.appendSlice(xs.items);
            }

            sortIntersections(T, &all);
            return all;
        }
    };
}

test "Intersection" {
    const allocator = testing.allocator;
    const tolerance = 1e-5;

    var w = try World(f32).default(allocator);
    defer w.destroy();

    const ray = Ray(f32).new(Tuple(f32).new_point(0.0, 0.0, -5.0), Tuple(f32).new_vec3(0.0, 0.0, 1.0));
    var xs = try w.intersect(allocator, ray);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 4);
    try testing.expectApproxEqAbs(xs.items[0].t, 4.0, tolerance);
    try testing.expectApproxEqAbs(xs.items[1].t, 4.5, tolerance);
    try testing.expectApproxEqAbs(xs.items[2].t, 5.5, tolerance);
    try testing.expectApproxEqAbs(xs.items[3].t, 6.0, tolerance);
}

