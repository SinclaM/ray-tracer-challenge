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
const Pattern = @import("../raytracer/patterns/pattern.zig").Pattern;

pub fn renderFresnel() !void {
    const allocator = std.heap.c_allocator;

    const identity = Matrix(f64, 4).identity();
    const solid_white = Pattern(f64).solid(Color(f64).new(0.85, 0.85, 0.85));
    const solid_black = Pattern(f64).solid(Color(f64).new(0.15, 0.15, 0.15));

    var backdrop = Shape(f64).plane();
    backdrop.material.ambient = 0.8;
    backdrop.material.diffuse = 0.2;
    backdrop.material.specular = 0.0;
    try backdrop.setTransform(identity.rotateX(pi / 2.0).translate(0.0, 0.0, 10.0));
    backdrop.material.pattern = Pattern(f64).checkers(&solid_black, &solid_white);

    var glass_sphere = Shape(f64).sphere();
    glass_sphere.material.color = Color(f64).new(1.0, 1.0, 1.0);
    glass_sphere.material.ambient = 0.0;
    glass_sphere.material.diffuse = 0.0;
    glass_sphere.material.specular = 0.9;
    glass_sphere.material.shininess = 300.0;
    glass_sphere.material.reflective = 0.9;
    glass_sphere.material.transparency = 0.9;
    glass_sphere.material.refractive_index = 1.5;

    var air_bubble = Shape(f64).sphere();
    air_bubble.material.color = Color(f64).new(1.0, 1.0, 1.0);
    air_bubble.material.ambient = 0.0;
    air_bubble.material.diffuse = 0.0;
    air_bubble.material.specular = 0.9;
    air_bubble.material.shininess = 300.0;
    air_bubble.material.reflective = 0.9;
    air_bubble.material.transparency = 0.9;
    air_bubble.material.refractive_index = 1.0000034;
    try air_bubble.setTransform(identity.scale(0.5, 0.5, 0.5));


    var world = World(f64).new(allocator);
    defer world.destroy();

    try world.objects.append(backdrop);
    try world.objects.append(glass_sphere);
    try world.objects.append(air_bubble);

    try world.lights.append(Light(f64).pointLight(
        Tuple(f64).point(2.0, 10.0, -5.0), Color(f64).new(0.9, 0.9, 0.9)
    ));

    var camera = Camera(f64).new(500, 500, 0.45);
    try camera.setTransform(
        Matrix(f64, 4).viewTransform(
            Tuple(f64).point(0.0, 0.0, -5.0), Tuple(f64).point(0.0, 0.0, 0.0), Tuple(f64).vec3(0.0, 1.0, 0.0)
        )
    );

    const canvas = try camera.render(allocator, world);
    defer canvas.destroy();

    const ppm = try canvas.ppm(allocator);
    defer allocator.free(ppm);

    const file = try std.fs.cwd().createFile(
        "images/fresnel.ppm",
        .{ .read = true },
    );
    defer file.close();

    _ = try file.writeAll(ppm);
}
