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
const Pattern = @import("patterns/pattern.zig").Pattern;

/// A `World` is a collection of `objects` and `lights`, backed
/// by floats of type `T`.
pub fn World(comptime T: type) type {
    return struct {
        const Self = @This();

        objects: ArrayList(Shape(T)),
        lights: ArrayList(Light(T)),

        /// Creates an empty world.
        ///
        /// Destroy with `destroy`.
        pub fn new(allocator: Allocator) Self {
            return .{ 
                .objects = ArrayList(Shape(T)).init(allocator),
                .lights = ArrayList(Light(T)).init(allocator)
            };
        }

        /// Creates the default world.
        ///
        /// Destroy with `destroy`.
        pub fn default(allocator: Allocator) !Self {
            var world = Self.new(allocator);

            var sphere1 = Shape(T).sphere();
            sphere1.material.pattern = Pattern(T).solid(Color(T).new(0.8, 1.0, 0.6));
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

        /// Frees the memory associated with `self`.
        pub fn destroy(self: Self) void {
            self.objects.deinit();
            self.lights.deinit();
        }
        
        /// Finds all the intersections of `ray` with objects in `self`.
        pub fn intersect(self: Self, allocator: Allocator, ray: Ray(T)) !Intersections(T) {
            var all = Intersections(T).init(allocator);

            for (self.objects.items) |*object| {
                const xs: Intersections(T) = try object.intersect(allocator, ray);
                defer xs.deinit();

                try all.appendSlice(xs.items);
            }

            sortIntersections(T, all.items);
            return all;
        }

        /// Computes the `Color` for the information in `comps` considering shadows.
        pub fn shadeHit(
            self: Self, allocator: Allocator, comps: PreComputations(T), remaining_recursions: usize
        ) !Color(T) {
            var surface = Color(T).new(0.0, 0.0, 0.0);

            for (self.lights.items) |light| {
                const shadowed = try self.isShadowed(allocator, comps.over_point, light);
                surface = surface.add(comps.intersection.object.material.lighting(
                    light, comps.intersection.object, comps.over_point, comps.eyev, comps.normal, shadowed
                ));
            }

            const reflected = try self.reflectedColor(allocator, comps, remaining_recursions);
            const refracted = try self.refractedColor(allocator, comps, remaining_recursions);

            if (comps.intersection.object.material.reflective > 0.0
                and comps.intersection.object.material.transparency > 0.0) {
                const reflectance = comps.schlick();
                return surface.add(reflected.mul(reflectance)).add(refracted.mul(1.0 - reflectance));
            } else {
                return surface.add(reflected).add(refracted);
            }
        }

        /// Determines the `Color` produced by intersecting `ray` with `self`.
        pub fn colorAt(self: Self, allocator: Allocator, ray: Ray(T), remaining_recursions: usize) !Color(T) {
            const xs = try self.intersect(allocator, ray);
            defer xs.deinit();

            if (hit(T, xs.items)) |hit_idx| {
                const comps = try PreComputations(T).new(allocator, xs.items[hit_idx], ray, xs);
                return self.shadeHit(allocator, comps, remaining_recursions);
            } else {
                return Color(T).new(0.0, 0.0, 0.0);
            }
        }

        /// Tests if `point` is shadowed, when considering the light source `light`.
        ///
        /// Assumes `point` is a point.
        pub fn isShadowed(self: Self, allocator: Allocator, point: Tuple(T), light: Light(T)) !bool {
            const direction = light.position.sub(point);
            const distance = direction.magnitude();

            const shadow_ray = Ray(T).new(point, direction.normalized());
            const intersections = try self.intersect(allocator, shadow_ray);
            defer intersections.deinit();

            var is_shadowed = false;

            // Check if any objects which do not opt out of shadow casting appear
            // in the intersections between the point and the light.
            var i = hit(T, intersections.items);
            while (i != null) {
                if (intersections.items[i.?].t < distance and intersections.items[i.?].object.casts_shadow) {
                    is_shadowed = true;
                    break;
                }

                const delta = hit(T, intersections.items[(i.? + 1)..]);
                if (delta != null) {
                    i = i.? + delta.? + 1;
                } else {
                    i = null;
                }
            }

            return is_shadowed;
        }

        /// Determines the color produced by reflection.
        fn reflectedColor(
            self: Self, allocator: Allocator, comps: PreComputations(T), remaining_recursions: usize
        ) anyerror!Color(T) {
            if (remaining_recursions == 0 or comps.intersection.object.material.reflective == 0.0) {
                return Color(T).new(0.0, 0.0, 0.0);
            } else {
                const reflected = Ray(T).new(comps.over_point, comps.reflectv);
                const color = try self.colorAt(allocator, reflected, remaining_recursions - 1);
                return color.mul(comps.intersection.object.material.reflective);
            }
        }


        /// Determines the color produced by refraction.
        fn refractedColor(
            self: Self, allocator: Allocator, comps: PreComputations(T), remaining_recursions: usize
        ) anyerror!Color(T) {
            const n_ratio = comps.n1 / comps.n2;
            const cos_i = comps.eyev.dot(comps.normal);
            const sin2_t = n_ratio * n_ratio * (1.0 - cos_i * cos_i);

            if (sin2_t > 1.0) {
                return Color(T).new(0.0, 0.0, 0.0);
            } else if (remaining_recursions == 0 or comps.intersection.object.material.transparency == 0.0) {
                return Color(T).new(0.0, 0.0, 0.0);
            } else {
                const cos_t = @sqrt(1.0 - sin2_t);
                const direction = comps.normal.mul(n_ratio * cos_i - cos_t).sub(comps.eyev.mul(n_ratio));
                const refracted = Ray(T).new(comps.under_point, direction);
                const color = try self.colorAt(allocator, refracted, remaining_recursions - 1);
                return color.mul(comps.intersection.object.material.transparency);
            }
        }
    };
}

/// A `PreComputations` object packages some useful data
/// for reuse in shading and lighting computations.
pub fn PreComputations(comptime T: type) type {
    return struct {
        const Self = @This();
        const epsilon = 1e-5;

        intersection: Intersection(T),
        point: Tuple(T),
        over_point: Tuple(T),
        under_point: Tuple(T),
        eyev: Tuple(T),
        normal: Tuple(T),
        inside: bool,
        reflectv: Tuple(T),
        n1: T,
        n2: T,

        /// Creates a new `PreComputations`.
        pub fn new(allocator: Allocator, hit_: Intersection(T), ray: Ray(T), xs: Intersections(T)) !Self {
            const point = ray.position(hit_.t);
            const eyev = ray.direction.negate();
            var normal = hit_.object.normalAt(point, hit_);
            var inside = false;

            if (normal.dot(eyev) < 0) {
                normal = normal.negate();
                inside = true;
            }

            const over_point = point.add(normal.mul(PreComputations(T).epsilon));
            const under_point = point.sub(normal.mul(PreComputations(T).epsilon));
            const reflectv = ray.direction.reflect(normal);


            // No BTree in the zig stdlib unfortunately.
            var containers = try ArrayList(*const Shape(T)).initCapacity(allocator, xs.items.len);
            defer containers.deinit();

            var n1: T = 1.0;
            var n2: T = 1.0;

            for (xs.items) |item| {
                const is_hit = item.t == hit_.t and item.object.id == hit_.object.id;
                if (is_hit and containers.items.len > 0) {
                    n1 = containers.items[containers.items.len - 1].material.refractive_index;
                }

                for (containers.items, 0..) |container, i| {
                    if (container.id == item.object.id) {
                        // Wish there was a BTree ...
                        _ = containers.orderedRemove(i);
                        break;
                    }
                } else {
                    try containers.append(item.object);
                }

                if (is_hit and containers.items.len > 0) {
                    n2 = containers.items[containers.items.len - 1].material.refractive_index;
                    break;
                }
            }


            return .{
                .intersection = hit_,
                .point = point,
                .over_point = over_point,
                .under_point = under_point,
                .eyev = eyev,
                .normal = normal,
                .inside = inside,
                .reflectv = reflectv,
                .n1 = n1,
                .n2 = n2
            };
        }

        fn schlick(self: Self) T {
            var cos = self.eyev.dot(self.normal);
            if (self.n1 > self.n2) {
                const n_ratio = self.n1 / self.n2;
                const sin2_t = n_ratio * n_ratio * (1.0 - cos * cos);
                if (sin2_t > 1.0) {
                    return 1.0;
                } else {
                    const cos_t = @sqrt(1.0 - sin2_t);
                    cos = cos_t;
                }
            }

            const frac = (self.n1 - self.n2) / (self.n1 + self.n2);
            const r0 = frac * frac;

            return r0 + (1.0 - r0) * std.math.pow(T, 1 - cos, 5);
        }
    };
}

test "Intersection" {
    const allocator = testing.allocator;
    const tolerance = 1e-5;

    const w = try World(f32).default(allocator);
    defer w.destroy();

    const ray = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
    const xs = try w.intersect(allocator, ray);
    defer xs.deinit();

    try testing.expectEqual(xs.items.len, 4);
    try testing.expectApproxEqAbs(xs.items[0].t, 4.0, tolerance);
    try testing.expectApproxEqAbs(xs.items[1].t, 4.5, tolerance);
    try testing.expectApproxEqAbs(xs.items[2].t, 5.5, tolerance);
    try testing.expectApproxEqAbs(xs.items[3].t, 6.0, tolerance);
}

test "PreComputations" {
    const allocator = testing.allocator;

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        const shape = Shape(f32).sphere();
        const i = Intersection(f32).new(4.0, &shape);
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);

        const comps = try PreComputations(f32).new(allocator, i, r, xs);

        try testing.expectEqual(comps.intersection, i);
        try testing.expect(comps.point.approxEqual(Tuple(f32).point(0.0, 0.0, -1.0)));
        try testing.expect(comps.eyev.approxEqual(Tuple(f32).vec3(0.0, 0.0, -1.0)));
        try testing.expect(comps.normal.approxEqual(Tuple(f32).vec3(0.0, 0.0, -1.0)));
        try testing.expectEqual(comps.inside, false);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        const shape = Shape(f32).sphere();
        const i =  Intersection(f32).new(1.0, &shape);
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);

        const comps = try PreComputations(f32).new(allocator, i, r, xs);

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
        const i =  Intersection(f32).new(5.0, &shape);
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);

        const comps = try PreComputations(f32).new(allocator, i, r, xs);

        try testing.expect(comps.over_point.z <  -PreComputations(f32).epsilon / 2.0);
        try testing.expect(comps.point.z > comps.over_point.z);
    }

    {
        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var shape = Shape(f32).glass_sphere();
        try shape.setTransform(Matrix(f32, 4).identity().translate(0.0, 0.0, 1.0));
        const i =  Intersection(f32).new(5.0, &shape);
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);

        const comps = try PreComputations(f32).new(allocator, i, r, xs);

        try testing.expect(comps.under_point.z > PreComputations(f32).epsilon / 2.0);
        try testing.expect(comps.point.z < comps.under_point.z);
    }
}

test "Shading" {
    const allocator = testing.allocator;

    {
        const w = try World(f32).default(allocator);
        defer w.destroy();

        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        const shape = w.objects.items[0];
        const i = Intersection(f32).new(4.0, &shape);
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);
        const comps = try PreComputations(f32).new(allocator, i, r, xs);
        try testing.expect(
            (try w.shadeHit(allocator, comps, 3)).approxEqual(Color(f32).new(0.38066, 0.47583, 0.2855))
        );
    }

    {
        const w = try World(f32).default(allocator);
        defer w.destroy();

        w.lights.items[0] = Light(f32).pointLight(
            Tuple(f32).point(0.0, 0.25, 0.0), Color(f32).new(1.0, 1.0, 1.0)
        );

        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        const shape = w.objects.items[1];
        const i = Intersection(f32).new(0.5, &shape);
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);
        const comps = try PreComputations(f32).new(allocator, i, r, xs);
        try testing.expect(
            (try w.shadeHit(allocator, comps, 3)).approxEqual(Color(f32).new(0.90498, 0.90498, 0.90498))
        );
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
        const i = Intersection(f32).new(4.0, &s2);
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);
        const comps = try PreComputations(f32).new(allocator, i, r, xs);
        try testing.expect(
            (try w.shadeHit(allocator, comps, 3)).approxEqual(Color(f32).new(0.1, 0.1, 0.1))
        );
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

        try testing.expect((try w.colorAt(allocator, r, 3)).approxEqual(Color(f32).new(0.0, 0.0, 0.0)));
    }

    {
        const w = try World(f32).default(allocator);
        defer w.destroy();

        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0)
        );

        try testing.expect((try w.colorAt(allocator, r, 3)).approxEqual(Color(f32).new(0.38066, 0.47583, 0.2855)));
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

        // Placeholder point. Solid pattern evaluates to same color everywhere.
        const point = Tuple(f32).point(0.0, 0.0, 0.0);

        try testing.expect(
            (try w.colorAt(allocator, r, 3))
                .approxEqual(inner.material.pattern.patternAtShape(inner, point))
        );
    }
}

test "isShadowed" {
    const allocator = testing.allocator;

    var w = try World(f32).default(allocator);
    defer w.destroy();

    var p = Tuple(f32).point(0.0, 10.0, 0.0);
    try testing.expectEqual(w.isShadowed(allocator, p, w.lights.items[0]), false);

    p = Tuple(f32).point(10.0, -10.0, 10.0);
    try testing.expectEqual(w.isShadowed(allocator, p, w.lights.items[0]), true);

    p = Tuple(f32).point(-20.0, 20.0, -20.0);
    try testing.expectEqual(w.isShadowed(allocator, p, w.lights.items[0]), false);

    p = Tuple(f32).point(-2.0, 2.0, -2.0);
    try testing.expectEqual(w.isShadowed(allocator, p, w.lights.items[0]), false);

    // Test opting out of shadow casting
    p = Tuple(f32).point(0.0, 0.0, 0.0);

    w.objects.items[0].casts_shadow = false;
    w.objects.items[1].casts_shadow = true;
    try testing.expectEqual(w.isShadowed(allocator, p, w.lights.items[0]), true);

    w.objects.items[0].casts_shadow = true;
    w.objects.items[1].casts_shadow = false;
    try testing.expectEqual(w.isShadowed(allocator, p, w.lights.items[0]), true);

    w.objects.items[0].casts_shadow = false;
    w.objects.items[1].casts_shadow = false;
    try testing.expectEqual(w.isShadowed(allocator, p, w.lights.items[0]), false);
}

test "Reflections" {
    const allocator = testing.allocator;

    {
        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 1.0, -1.0), Tuple(f32).vec3(0.0, -1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0))
        );

        var shape = Shape(f32).plane();
        const i =  Intersection(f32).new(@sqrt(2.0), &shape);
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);

        const comps = try PreComputations(f32).new(allocator, i, r, xs);

        try testing.expect(comps.reflectv.approxEqual(Tuple(f32).vec3(0.0, 1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0))));
    }

    {
        const w = try World(f32).default(allocator);
        defer w.destroy();
        const r = Ray(f32).new(Tuple(f32).point(0.0, 1.0, 0.0), Tuple(f32).vec3(0.0, 0.0, 1.0));

        var shape = w.objects.items[1];
        const i =  Intersection(f32).new(1.0, &shape);
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);

        const comps = try PreComputations(f32).new(allocator, i, r, xs);
        const color = try w.reflectedColor(allocator, comps, 3);

        try testing.expectEqual(color, Color(f32).new(0.0, 0.0, 0.0));
    }

    {
        var w = try World(f32).default(allocator);
        defer w.destroy();

        var shape = Shape(f32).plane();
        shape.material.reflective = 0.5;
        try shape.setTransform(Matrix(f32, 4).identity().translate(0.0, -1.0, 0.0));
        try w.objects.append(shape);

        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, -3.0), Tuple(f32).vec3(0.0, -1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0))
        );

        const i =  Intersection(f32).new(@sqrt(2.0), &shape);

        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);
        const comps = try PreComputations(f32).new(allocator, i, r, xs);
        const color = try w.reflectedColor(allocator, comps, 3);

        try testing.expect(color.approxEqual(Color(f32).new(0.19033, 0.23791, 0.14275)));
    }
    {
        var w = try World(f32).default(allocator);
        defer w.destroy();

        var shape = Shape(f32).plane();
        shape.material.reflective = 0.5;
        try shape.setTransform(Matrix(f32, 4).identity().translate(0.0, -1.0, 0.0));
        try w.objects.append(shape);

        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, -3.0), Tuple(f32).vec3(0.0, -1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0))
        );

        const i =  Intersection(f32).new(@sqrt(2.0), &shape);

        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);
        const comps = try PreComputations(f32).new(allocator, i, r, xs);
        const color = try w.shadeHit(allocator, comps, 3);

        try testing.expect(color.approxEqual(Color(f32).new(0.87676, 0.92434, 0.82917)));
    }

    {
        var w = try World(f32).default(allocator);
        defer w.destroy();

        var shape = Shape(f32).plane();
        shape.material.reflective = 0.5;
        try shape.setTransform(Matrix(f32, 4).identity().translate(0.0, -1.0, 0.0));
        try w.objects.append(shape);

        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, -3.0), Tuple(f32).vec3(0.0, -1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0))
        );

        const i =  Intersection(f32).new(@sqrt(2.0), &shape);

        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);
        const comps = try PreComputations(f32).new(allocator, i, r, xs);
        const color = try w.shadeHit(allocator, comps, 3);

        try testing.expect(color.approxEqual(Color(f32).new(0.87676, 0.92434, 0.82917)));
    }

    {
        var w = World(f32).new(allocator);
        defer w.destroy();

        try w.lights.append(
            Light(f32).pointLight(Tuple(f32).point(0.0, 0.0, 0.0), Color(f32).new(1.0, 1.0, 1.0))
        );

        var lower = Shape(f32).plane();
        lower.material.reflective = 1.0;
        try lower.setTransform(Matrix(f32, 4).identity().translate(0.0, -1.0, 0.0));
        try w.objects.append(lower);

        var upper = Shape(f32).plane();
        upper.material.reflective = 1.0;
        try upper.setTransform(Matrix(f32, 4).identity().translate(0.0, 1.0, 0.0));
        try w.objects.append(upper);

        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 1.0, 0.0));
        _ = try w.colorAt(allocator, r, 3);
    }

    {
        var w = try World(f32).default(allocator);
        defer w.destroy();

        var shape = Shape(f32).plane();
        shape.material.reflective = 0.5;
        try shape.setTransform(Matrix(f32, 4).identity().translate(0.0, -1.0, 0.0));
        try w.objects.append(shape);

        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, -3.0), Tuple(f32).vec3(0.0, -1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0))
        );

        const i =  Intersection(f32).new(@sqrt(2.0), &shape);

        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(i);
        const comps = try PreComputations(f32).new(allocator, i, r, xs);
        const color = try w.reflectedColor(allocator, comps, 0);

        try testing.expect(color.approxEqual(Color(f32).new(0.0, 0.0, 0.0)));
    }
}

test "Refraction base cases" {
    const allocator = testing.allocator;

    {
        const w = try World(f32).default(allocator);
        defer w.destroy();

        var shape = w.objects.items[0];

        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();

        try xs.append(Intersection(f32).new(4.0, &shape));
        try xs.append(Intersection(f32).new(6.0, &shape));

        const comps = try PreComputations(f32).new(allocator, xs.items[0], r, xs);
        const c = try w.refractedColor(allocator, comps, 3);

        try testing.expectEqual(c, Color(f32).new(0.0, 0.0, 0.0));
    }

    {
        const w = try World(f32).default(allocator);
        defer w.destroy();

        var shape = w.objects.items[0];
        shape.material.transparency = 1.0;
        shape.material.refractive_index = 1.5;

        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, -5.0), Tuple(f32).vec3(0.0, 0.0, 1.0));
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();

        try xs.append(Intersection(f32).new(4.0, &shape));
        try xs.append(Intersection(f32).new(6.0, &shape));

        const comps = try PreComputations(f32).new(allocator, xs.items[0], r, xs);
        const c = try w.refractedColor(allocator, comps, 0);

        try testing.expectEqual(c, Color(f32).new(0.0, 0.0, 0.0));
    }
}

test "Total internal reflection" {
    const allocator = testing.allocator;

    const w = try World(f32).default(allocator);
    defer w.destroy();
    var shape = w.objects.items[0];
    shape.material.transparency = 1.0;
    shape.material.refractive_index = 1.5;

    const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 1.0 / @sqrt(2.0)), Tuple(f32).vec3(0.0, 1.0, 0.0));

    var xs = Intersections(f32).init(allocator);
    defer xs.deinit();
    try xs.append(Intersection(f32).new(- 1.0 / @sqrt(2.0), &shape));
    try xs.append(Intersection(f32).new(1.0 / @sqrt(2.0), &shape));

    const comps = try PreComputations(f32).new(allocator, xs.items[1], r, xs);
    const c = try w.refractedColor(allocator, comps, 5);

    try testing.expectEqual(c, Color(f32).new(0.0, 0.0, 0.0));
}

test "Recursive refraction" {
    const allocator = testing.allocator;

    {
        const w = try World(f32).default(allocator);
        defer w.destroy();

        var a = &w.objects.items[0];
        a.material.ambient = 1.0;
        a.material.pattern = Pattern(f32).testPattern();

        var b = &w.objects.items[1];
        b.material.transparency = 1.0;
        b.material.refractive_index = 1.5;

        const r = Ray(f32).new(Tuple(f32).point(0.0, 0.0, 0.1), Tuple(f32).vec3(0.0, 1.0, 0.0));

        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(Intersection(f32).new(-0.9899, &a.*));
        try xs.append(Intersection(f32).new(-0.4899, &b.*));
        try xs.append(Intersection(f32).new(0.4899, &b.*));
        try xs.append(Intersection(f32).new(0.9899, &a.*));

        const comps = try PreComputations(f32).new(allocator, xs.items[2], r, xs);
        const c = try w.refractedColor(allocator, comps, 5);

        try testing.expect(c.approxEqual(Color(f32).new(0.0, 0.99887, 0.04721)));
    }

    {
        var w = try World(f32).default(allocator);
        defer w.destroy();

        var floor = Shape(f32).plane();
        try floor.setTransform(Matrix(f32, 4).identity().translate(0.0, -1.0, 0.0));
        floor.material.transparency = 0.5;
        floor.material.refractive_index = 1.5;

        var ball = Shape(f32).sphere();
        try ball.setTransform(Matrix(f32, 4).identity().translate(0.0, -3.5, -0.5));
        ball.material.pattern = Pattern(f32).solid(Color(f32).new(1.0, 0.0, 0.0));
        ball.material.ambient = 0.5;

        try w.objects.append(floor);
        try w.objects.append(ball);

        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, -3.0), Tuple(f32).vec3(0.0, -1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0))
        );

        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(Intersection(f32).new(@sqrt(2.0), &floor));
        const comps = try PreComputations(f32).new(allocator, xs.items[0], r, xs);

        const color = try w.shadeHit(allocator, comps, 5);

        try testing.expect(color.approxEqual(Color(f32).new(0.93642, 0.68642, 0.68642)));
    }
}

test "Schlick" {
    const allocator = testing.allocator;
    const tolerance = 1e-5;

    {
        const shape = Shape(f32).glass_sphere();
        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, 1.0 / @sqrt(2.0)), Tuple(f32).vec3(0.0, 1.0, 0.0)
        );
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(Intersection(f32).new(-1.0 / @sqrt(2.0), &shape));
        try xs.append(Intersection(f32).new(1.0 / @sqrt(2.0), &shape));

        const comps = try PreComputations(f32).new(allocator, xs.items[1], r, xs);
        const reflectance = comps.schlick();

        try testing.expectEqual(reflectance, 1.0);
    }

    {
        const shape = Shape(f32).glass_sphere();
        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, 0.0), Tuple(f32).vec3(0.0, 1.0, 0.0)
        );
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(Intersection(f32).new(-1.0, &shape));
        try xs.append(Intersection(f32).new(1.0, &shape));

        const comps = try PreComputations(f32).new(allocator, xs.items[1], r, xs);
        const reflectance = comps.schlick();

        try testing.expectApproxEqAbs(reflectance, 0.04, tolerance);
    }

    {
        const shape = Shape(f32).glass_sphere();
        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.99, -2.0), Tuple(f32).vec3(0.0, 0.0, 1.0)
        );
        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();
        try xs.append(Intersection(f32).new(1.8589, &shape));

        const comps = try PreComputations(f32).new(allocator, xs.items[0], r, xs);
        const reflectance = comps.schlick();

        try testing.expectApproxEqAbs(reflectance, 0.48873, tolerance);
    }

    {
        var w = try World(f32).default(allocator);
        defer w.destroy();

        const r = Ray(f32).new(
            Tuple(f32).point(0.0, 0.0, -3.0), Tuple(f32).vec3(0.0, -1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0))
        );

        var floor = Shape(f32).plane();
        try floor.setTransform(Matrix(f32, 4).identity().translate(0.0, -1.0, 0.0));
        floor.material.reflective = 0.5;
        floor.material.transparency = 0.5;
        floor.material.refractive_index = 1.5;

        var ball = Shape(f32).sphere();
        try ball.setTransform(Matrix(f32, 4).identity().translate(0.0, -3.5, -0.5));
        ball.material.pattern = Pattern(f32).solid(Color(f32).new(1.0, 0.0, 0.0));
        ball.material.ambient = 0.5;

        try w.objects.append(floor);
        try w.objects.append(ball);

        var xs = Intersections(f32).init(allocator);
        defer xs.deinit();

        try xs.append(Intersection(f32).new(@sqrt(2.0), &floor));
        const comps = try PreComputations(f32).new(allocator, xs.items[0], r, xs);

        const color = try w.shadeHit(allocator, comps, 5);

        try testing.expect(color.approxEqual(Color(f32).new(0.93391, 0.69643, 0.69243)));
    }
}
