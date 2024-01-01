const std = @import("std");

const Color = @import("../raytracer/color.zig").Color;
const Canvas = @import("../raytracer/canvas.zig").Canvas;
const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Matrix = @import("../raytracer/matrix.zig").Matrix;
const Ray = @import("../raytracer/ray.zig").Ray;
const Shape = @import("../raytracer/shapes/shape.zig").Shape;
const hit = @import("../raytracer/shapes/shape.zig").hit;
const sortIntersections = @import("../raytracer/shapes/shape.zig").sortIntersections;

pub fn drawSilhouette() !void {
    const canvas_size = 100;

    const allocator = std.heap.c_allocator;

    var canvas = try Canvas(f32).new(allocator, canvas_size, canvas_size);
    defer canvas.destroy();

    var s = Shape(f32).sphere();
    try s.setTransform(Matrix(f32, 4).identity().scale(1.3, 1.0, 1.0).translate(0.5, 0.5, 0.0));
    const source = Tuple(f32).point(0.0, 0.0, -5.0);

    const wall_size: f32 = 13.0;
    const wall_z: f32 = 10.0;
    const pixel_size: f32 = wall_size / canvas_size;

    for (0..canvas_size) |x| {
        for (0..canvas_size) |y| {
            const pos = Tuple(f32).point(
                - wall_size / 2.0 + pixel_size * @as(f32, @floatFromInt(x)),
                wall_size / 2.0 - pixel_size * @as(f32, @floatFromInt(y)),
                wall_z
            );

            const direction = pos.sub(source).normalized();

            const ray = Ray(f32).new(source, direction);
            const xs = try s.intersect(allocator, ray);
            defer xs.deinit();
            sortIntersections(f32, xs.items);
            if (hit(f32, xs.items)) |_| {
                canvas.getPixelPointerMut(x, y).?.* = Color(f32).new(1.0, 0.0, 0.0);
            }

        }
    }

    var image = try canvas.to_image(allocator);
    defer image.deinit();

    try image.writeToFilePath("images" ++ std.fs.path.sep_str ++ "silhouette.png", .{ .png = .{} });
}
