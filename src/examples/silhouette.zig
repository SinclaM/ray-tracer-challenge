const std = @import("std");
const print = std.debug.print;

const Color = @import("../raytracer/color.zig").Color;
const Canvas = @import("../raytracer/canvas.zig").Canvas;
const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Matrix = @import("../raytracer/matrix.zig").Matrix;
const Ray = @import("../raytracer/ray.zig").Ray;
const Sphere = @import("../raytracer/shapes/sphere.zig").Sphere;
const hit = @import("../raytracer/shapes/sphere.zig").hit;

pub fn drawSilhouette() !void {
    comptime var canvas_size = 100;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var canvas = try Canvas(f32).new(allocator, canvas_size, canvas_size);

    var s = Sphere(f32).new();
    s.transform = Matrix(f32, 4).identity().scale(1.3, 1.0, 1.0).translate(0.5, 0.5, 0.0);
    const source = Tuple(f32).new_point(0.0, 0.0, -5.0);

    const wall_size: f32 = 13.0;
    const wall_z: f32 = 10.0;
    const pixel_size: f32 = wall_size / canvas_size;

    var x: usize = 0;
    while (x < canvas_size) : (x += 1) {
        var y: usize = 0;
        while (y < canvas_size) : (y += 1) {
            const pos = Tuple(f32).new_point(
                - wall_size / 2.0 + pixel_size * @intToFloat(f32, x),
                wall_size / 2.0 - pixel_size * @intToFloat(f32, y),
                wall_z
            );

            const direction = pos.sub(source).normalized();

            const ray = Ray(f32).new(source, direction);
            var xs = try s.intersect(allocator, ray);
            if (hit(f32, &xs)) |_| {
                canvas.get_pixel_pointer(x, y).?.* = Color(f32).new(1.0, 0.0, 0.0);
            }

        }
    }

    const ppm = try canvas.as_ppm(allocator);

    const file = try std.fs.cwd().createFile(
        "images/silhouette.ppm",
        .{ .read = true },
    );
    defer file.close();

    _ = try file.writeAll(ppm);
}
