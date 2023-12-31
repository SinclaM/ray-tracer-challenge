const std = @import("std");

const Color = @import("../raytracer/color.zig").Color;
const Canvas = @import("../raytracer/canvas.zig").Canvas;
const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Matrix = @import("../raytracer/matrix.zig").Matrix;
const Ray = @import("../raytracer/ray.zig").Ray;
const Shape = @import("../raytracer/shapes/shape.zig").Shape;
const hit = @import("../raytracer/shapes/shape.zig").hit;
const sortIntersections = @import("../raytracer/shapes/shape.zig").sortIntersections;
const Light = @import("../raytracer/light.zig").Light;
const Pattern = @import("../raytracer//patterns/pattern.zig").Pattern;

pub fn drawSphere() !void {
    const canvas_size = 1000;

    const allocator = std.heap.c_allocator;

    var canvas = try Canvas(f32).new(allocator, canvas_size, canvas_size);
    defer canvas.destroy();

    var s = Shape(f32).sphere();
    s.material.pattern = Pattern(f32).solid(Color(f32).new(1.0, 0.2, 1.0));

    const eye = Tuple(f32).point(0.0, 0.0, -5.0);

    const light = Light(f32).pointLight(
        Tuple(f32).point(-10.0, 10.0, -10.0), Color(f32).new(1.0, 1.0, 1.0)
    );

    const wall_size: f32 = 7.0;
    const wall_z: f32 = 10.0;
    const pixel_size: f32 = wall_size / canvas_size;

    for (0..canvas_size) |x| {
        for (0..canvas_size) |y| {
            const pos = Tuple(f32).point(
                - wall_size / 2.0 + pixel_size * @as(f32, @floatFromInt(x)),
                wall_size / 2.0 - pixel_size * @as(f32, @floatFromInt(y)),
                wall_z
            );

            const direction = pos.sub(eye).normalized();

            const ray = Ray(f32).new(eye, direction);
            const xs = try s.intersect(allocator, ray);
            defer xs.deinit();
            sortIntersections(f32, xs.items);
            if (hit(f32, xs.items)) |hit_| {
                const point = ray.position(xs.items[hit_].t);
                const normal = s.normalAt(point, xs.items[hit_]);
                const eyev = ray.direction.negate();
                const color = s.material.lighting(light, &s, point, eyev, normal, false);
                canvas.getPixelPointerMut(x, y).?.* = color;
            }

        }
    }

    var image = try canvas.to_image(allocator);
    defer image.deinit();

    try image.writeToFilePath("images" ++ std.fs.path.sep_str ++ "sphere.png", .{ .png = .{} });
}
