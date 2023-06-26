const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Tuple = @import("tuple.zig").Tuple;
const Matrix = @import("matrix.zig").Matrix;
const Ray = @import("ray.zig").Ray;
const Color = @import("color.zig").Color;
const Light = @import("light.zig").Light;
const Intersection = @import("shapes/shape.zig").Intersection;
const Intersections = @import("shapes/shape.zig").Intersections;
const sortIntersections = @import("shapes/shape.zig").sortIntersections;
const hit = @import("shapes/shape.zig").hit;
const Shape = @import("shapes/shape.zig").Shape;

pub fn World(comptime T: type) type {
    return struct {
        const Self = @This();

        objects: ArrayList(Shape(T)),
        lights: ArrayList(Light(T)),

        pub fn new(allocator: Allocator) Self {
            return .{ 
                .objects = ArrayList(Shape(T)).init(allocator),
                .lights = ArrayList(Light(T)).init(allocator)
            };
        }

        pub fn default(allocator: Allocator) !Self {
            var world = Self.new(allocator);

            var sphere1 = Shape(T).sphere();
            sphere1.material.color = Color(T).new(0.8, 1.0, 0.6);
            sphere1.material.diffuse = 0.7;
            sphere1.material.specular = 0.2;

            var sphere2 = Shape(T).sphere();
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

            for (self.objects.items) |*object| {
                var xs: Intersections(T) = try object.intersect(allocator, ray);
                defer xs.deinit();

                try all.appendSlice(xs.items);
            }

            sortIntersections(T, &all);
            return all;
        }

        pub fn shadeHit(self: Self, allocator: Allocator, comps: PreComputations(T)) !Color(T) {
            var color = Color(T).new(0.0, 0.0, 0.0);

            for (self.lights.items) |light| {
                const shadowed = try self.isShadowed(allocator, comps.over_point, light);
                color = color.add(comps.intersection.object.material.lighting(
                    light, comps.point, comps.eyev, comps.normal, shadowed
                ));
            }

            return color;
        }

        pub fn colorAt(self: Self, allocator: Allocator, ray: Ray(T)) !Color(T) {
            var xs = try self.intersect(allocator, ray);
            defer xs.deinit();

            if (hit(T, xs)) |hit_| {
                const comps = PreComputations(T).new(hit_, ray);
                return try self.shadeHit(allocator, comps);
            } else {
                return Color(T).new(0.0, 0.0, 0.0);
            }
        }

        pub fn isShadowed(self: Self, allocator: Allocator, point: Tuple(T), light: Light(T)) !bool {
            const direction = light.position.sub(point);
            const distance = direction.magnitude();

            const shadow_ray = Ray(T).new(point, direction.normalized());
            const intersections = try self.intersect(allocator, shadow_ray);
            defer intersections.deinit();

            const hit_ = hit(T, intersections);
            return hit_ != null and hit_.?.t < distance;
        }
    };
}

pub fn PreComputations(comptime T: type) type {
    return struct {
        const Self = @This();
        const epsilon = 1e-5;

        intersection: Intersection(T),
        point: Tuple(T),
        over_point: Tuple(T),
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

            const over_point = point.add(normal.mul(PreComputations(T).epsilon));
            
            return .{
                .intersection = intersection,
                .point = point,
                .over_point = over_point,
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
        const shape = Shape(f32).sphere();
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
        const shape = Shape(f32).sphere();
        const i =  Intersection(f32).new(1.0, shape);

        const comps = PreComputations(f32).new(i, r);

        try testing.expectEqual(comps.intersection, i);
        try testing.expect(comps.point.approxEqual(Tuple(f32).point(0.0, 0.0, 1.0)));
        try testing.expect(comps.eyev.approxEqual(Tuple(f32).vec3(0.0, 0.0, -1.0)));
        try testing.expect(comps.normal.approxEqual(Tuple(f32).vec3(0.0, 0.0, -1.0)));
        try testing.expectEqual(comps.inside, true);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var shape = Shape(f32).sphere();
        try shape.setTransform(Matrix(f32, 4).identity().translate(0.0, 0.0, 1.0));
        const i =  Intersection(f32).new(5.0, shape);

        const comps = PreComputations(f32).new(i, r);

        try testing.expect(comps.over_point.z <  -PreComputations(f32).epsilon / 2.0);
        try testing.expect(comps.point.z > comps.over_point.z);
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
        try testing.expect((try w.shadeHit(allocator, comps)).approxEqual(Color(f32).new(0.38066, 0.47583, 0.2855)));
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
        try testing.expect((try w.shadeHit(allocator, comps)).approxEqual(Color(f32).new(0.90498, 0.90498, 0.90498)));
    }

    {
        var w = World(f32).new(allocator);
        defer w.destroy();

        try w.lights.append(Light(f32).pointLight(
            Tuple(f32).point(0.0, 0.0, -10.0), Color(f32).new(1.0, 1.0, 1.0)
        ));

        const s1 = Shape(f32).sphere();
        try w.objects.append(s1);

        var s2 = Shape(f32).sphere();
        try s2.setTransform(Matrix(f32, 4).identity().translate(0.0, 0.0, 10.0));
        try w.objects.append(s2);

        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        const i = Intersection(f32).new(4.0, s2);
        const comps = PreComputations(f32).new(i, r);
        try testing.expect((try w.shadeHit(allocator, comps)).approxEqual(Color(f32).new(0.1, 0.1, 0.1)));
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

test "isShadowed" {
    const allocator = testing.allocator;

    const w = try World(f32).default(allocator);
    defer w.destroy();

    var p = Tuple(f32).point(0.0, 10.0, 0.0);
    try testing.expectEqual(w.isShadowed(allocator, p, w.lights.items[0]), false);

    p = Tuple(f32).point(10.0, -10.0, 10.0);
    try testing.expectEqual(w.isShadowed(allocator, p, w.lights.items[0]), true);

    p = Tuple(f32).point(-20.0, 20.0, -20.0);
    try testing.expectEqual(w.isShadowed(allocator, p, w.lights.items[0]), false);

    p = Tuple(f32).point(-2.0, 2.0, -2.0);
    try testing.expectEqual(w.isShadowed(allocator, p, w.lights.items[0]), false);
}
