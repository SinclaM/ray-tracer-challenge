const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Tuple = @import("tuple.zig").Tuple;
const Matrix = @import("matrix.zig").Matrix;
const Ray = @import("ray.zig").Ray;
const Color = @import("color.zig").Color;
const Light = @import("light.zig").Light;
const Intersection = @import("shapes/sphere.zig").Intersection;
const Intersections = @import("shapes/sphere.zig").Intersections;
const sortIntersections = @import("shapes/sphere.zig").sortIntersections;
const hit = @import("shapes/sphere.zig").hit;
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
            sphere2.setTransform(Matrix(T, 4).identity().scale(0.5, 0.5, 0.5)) catch unreachable;

            try world.objects.append(sphere1);
            try world.objects.append(sphere2);

            var light = Light(T).pointLight(
                Tuple(T).point(-10.0, 10.0, -10.0),
                Color(T).new(1.0, 1.0, 1.0)
            );

            try world.lights.append(light);

            return world;
        }

        pub fn destroy(self: Self) void {
            self.objects.deinit();
            self.lights.deinit();
        }
        
        pub fn intersect(self: Self, allocator: Allocator, ray: Ray(T)) !Intersections(T) {
            var all = Intersections(T).init(allocator);

            for (self.objects.items) |object| {
                var xs: Intersections(T) = try object.intersect(allocator, ray);
                defer xs.deinit();

                try all.appendSlice(xs.items);
            }

            sortIntersections(T, &all);
            return all;
        }

        pub fn shadeHit(self: Self, comps: PreComputations(T)) Color(T) {
            var color = Color(T).new(0.0, 0.0, 0.0);

            for (self.lights.items) |light| {
                color = color.add(comps.intersection.object.material.lighting(
                    light, comps.point, comps.eyev, comps.normal
                ));
            }

            return color;
        }

        pub fn colorAt(self: Self, allocator: Allocator, ray: Ray(T)) !Color(T) {
            var xs = try self.intersect(allocator, ray);
            defer xs.deinit();

            if (hit(T, xs)) |hit_| {
                const comps = PreComputations(T).new(hit_, ray);
                return self.shadeHit(comps);
            } else {
                return Color(T).new(0.0, 0.0, 0.0);
            }
        }
    };
}

pub fn PreComputations(comptime T: type) type {
    return struct {
        const Self = @This();
        intersection: Intersection(T),
        point: Tuple(T),
        eyev: Tuple(T),
        normal: Tuple(T),
        inside: bool,

        pub fn new(intersection: Intersection(T), ray: Ray(T)) Self {
            const point = ray.position(intersection.t);
            const eyev = ray.direction.negate();
            var normal = intersection.object.normalAt(point);
            var inside = false;

            if (normal.dot(eyev) < 0) {
                normal = normal.negate();
                inside = true;
            }
            
            return .{
                .intersection = intersection,
                .point = point,
                .eyev = eyev,
                .normal = normal,
                .inside = inside
            };
        }
    };
}

test "Intersection" {
    const allocator = testing.allocator;
    const tolerance = 1e-5;

    var w = try World(f32).default(allocator);
    defer w.destroy();

    const ray = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
    var xs = try w.intersect(allocator, ray);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 4);
    try testing.expectApproxEqAbs(xs.items[0].t, 4.0, tolerance);
    try testing.expectApproxEqAbs(xs.items[1].t, 4.5, tolerance);
    try testing.expectApproxEqAbs(xs.items[2].t, 5.5, tolerance);
    try testing.expectApproxEqAbs(xs.items[3].t, 6.0, tolerance);
}

test "PreComputations" {
    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        const shape = Sphere(f32).new();
        const i: Intersection(f32) = .{ .t = 4, .object = shape };

        const comps = PreComputations(f32).new(i, r);

        try testing.expectEqual(comps.intersection, i);
        try testing.expect(comps.point.approxEqual(Tuple(f32).point(0.0, 0.0, -1.0)));
        try testing.expect(comps.eyev.approxEqual(Tuple(f32).vec3(0.0, 0.0, -1.0)));
        try testing.expect(comps.normal.approxEqual(Tuple(f32).vec3(0.0, 0.0, -1.0)));
        try testing.expectEqual(comps.inside, false);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        const shape = Sphere(f32).new();
        const i =  Intersection(f32).new(1.0, shape);

        const comps = PreComputations(f32).new(i, r);

        try testing.expectEqual(comps.intersection, i);
        try testing.expect(comps.point.approxEqual(Tuple(f32).point(0.0, 0.0, 1.0)));
        try testing.expect(comps.eyev.approxEqual(Tuple(f32).vec3(0.0, 0.0, -1.0)));
        try testing.expect(comps.normal.approxEqual(Tuple(f32).vec3(0.0, 0.0, -1.0)));
        try testing.expectEqual(comps.inside, true);
    }
}

test "Shading" {
    const allocator = testing.allocator;

    {
        const w = try World(f32).default(allocator);
        defer w.destroy();

        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        const shape = w.objects.items[0];
        const i = Intersection(f32).new(4.0, shape);
        const comps = PreComputations(f32).new(i, r);
        try testing.expect(w.shadeHit(comps).approxEqual(Color(f32).new(0.38066, 0.47583, 0.2855)));
    }

    {
        const w = try World(f32).default(allocator);
        defer w.destroy();

        w.lights.items[0] = Light(f32).pointLight(
            Tuple(f32).point(0.0, 0.25, 0.0), Color(f32).new(1.0, 1.0, 1.0)
        );

        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        const shape = w.objects.items[1];
        const i = Intersection(f32).new(0.5, shape);
        const comps = PreComputations(f32).new(i, r);
        try testing.expect(w.shadeHit(comps).approxEqual(Color(f32).new(0.90498, 0.90498, 0.90498)));
    }
}

test "Coloring" {
    const allocator = testing.allocator;

    {
        const w = try World(f32).default(allocator);
        defer w.destroy();

        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 1.0, 0.0)
        );

        try testing.expect((try w.colorAt(allocator, r)).approxEqual(Color(f32).new(0.0, 0.0, 0.0)));
    }

    {
        const w = try World(f32).default(allocator);
        defer w.destroy();

        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0)
        );

        try testing.expect((try w.colorAt(allocator, r)).approxEqual(Color(f32).new(0.38066, 0.47583, 0.2855)));
    }

    {
        var w = try World(f32).default(allocator);
        defer w.destroy();

        var outer = &w.objects.items[0];
        outer.*.material.ambient = 1.0;
        var inner = &w.objects.items[1];
        inner.*.material.ambient = 1.0;

        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, 0.75), Tuple(f32).vec3(0.0, 0.0, -1.0)
        );

        try testing.expect((try w.colorAt(allocator, r)).approxEqual(inner.material.color));
    }
}
