const std = @import("std");
const pi = std.math.pi;

const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Matrix = @import("../raytracer/matrix.zig").Matrix;
const Color = @import("../raytracer/color.zig").Color;
const Material = @import("../raytracer/material.zig").Material;
const Shape = @import("../raytracer/shapes/shape.zig").Shape;
const Light = @import("../raytracer/light.zig").Light;
const World = @import("../raytracer/world.zig").World;
const Camera = @import("../raytracer/camera.zig").Camera;

pub fn renderSimpleSuperflat() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const identity = Matrix(f64, 4).identity();

    var floor = Shape(f64).plane();
    floor.material.color = Color(f64).new(1, 0.9, 0.9);
    floor.material.specular = 0.0;

    var large = Shape(f64).sphere();
    try large.setTransform(identity.translate(-0.5, 1.0, 0.5).scale(1.0, 0.5, 1.0));
    large.material.color = Color(f64).new(0.1, 1.0, 0.5);
    large.material.diffuse = 0.7;
    large.material.specular = 0.3;

    var small = Shape(f64).sphere();
    try small.setTransform(identity.scale(0.5, 0.5, 0.5).translate(1.5, 0.5, -0.5));
    small.material.color = Color(f64).new(0.5, 1.0, 0.1);
    small.material.diffuse = 0.7;
    small.material.specular = 0.3;

    var tiny = Shape(f64).sphere();
    try tiny.setTransform(
        identity
            .scale(0.25, 0.25, 0.25)
            .translate(1.5, 1.25, -0.5)
    );
    tiny.material.color = Color(f64).new(1.0, 0.2, 1.0);
    tiny.material.diffuse = 0.7;
    tiny.material.specular = 0.3;


    var world = World(f64).new(allocator);
    try world.objects.append(floor);
    try world.objects.append(large);
    try world.objects.append(small);
    try world.objects.append(tiny);

    try world.lights.append(Light(f64).pointLight(
        Tuple(f64).point(-10.0, 10.0, -10.0), Color(f64).new(0.953, 0.51, 0.208)
    ));

    var camera = Camera(f64).new(1000, 500, pi / 3.0);
    try camera.setTransform(
        Matrix(f64, 4).viewTransform(
            Tuple(f64).point(0.0, 1.3, -5.0), Tuple(f64).point(1.0, 1.0, 0.0), Tuple(f64).vec3(0.0, 1.0, 0.0)
        )
    );

    const canvas = try camera.render(allocator, world);

    const ppm = try canvas.ppm(allocator);

    const file = try std.fs.cwd().createFile(
        "images/simple_superflat.ppm",
        .{ .read = true },
    );
    defer file.close();

    _ = try file.writeAll(ppm);
}
