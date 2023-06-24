const std = @import("std");
const pi = std.math.pi;

const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Matrix = @import("../raytracer/matrix.zig").Matrix;
const Color = @import("../raytracer/color.zig").Color;
const Material = @import("../raytracer/material.zig").Material;
const Sphere = @import("../raytracer/shapes/sphere.zig").Sphere;
const Light = @import("../raytracer/light.zig").Light;
const World = @import("../raytracer/world.zig").World;
const Camera = @import("../raytracer/camera.zig").Camera;

pub fn renderSimpleWorld() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const identity = Matrix(f32, 4).identity();

    var floor = Sphere(f32).new();
    try floor.setTransform(identity.scale(10.0, 0.01, 10.0));
    floor.material.color = Color(f32).new(1, 0.9, 0.9);
    floor.material.specular = 0.0;

    var left_wall = Sphere(f32).new();
    try left_wall.setTransform(
        identity
            .scale(10.0, 0.01, 10.0)
            .rotateX(pi / 2.0)
            .rotateY(-pi / 4.0)
            .translate(0.0, 0.0, 5.0)
    );
    left_wall.material.color = Color(f32).new(1, 0.9, 0.9);
    left_wall.material.specular = 0.0;

    var right_wall = Sphere(f32).new();
    try right_wall.setTransform(
        identity
            .scale(10.0, 0.01, 10.0)
            .rotateX(pi / 2.0)
            .rotateY(pi / 4.0)
            .translate(0.0, 0.0, 5.0)
    );
    right_wall.material.color = Color(f32).new(1, 0.9, 0.9);
    right_wall.material.specular = 0.0;

    var middle = Sphere(f32).new();
    try middle.setTransform(identity.translate(-0.5, 1.0, 0.5));
    middle.material.color = Color(f32).new(0.1, 1.0, 0.5);
    middle.material.diffuse = 0.7;
    middle.material.specular = 0.3;

    var right = Sphere(f32).new();
    try right.setTransform(identity.scale(0.5, 0.5, 0.5).translate(1.5, 0.5, -0.5));
    right.material.color = Color(f32).new(0.5, 1.0, 0.1);
    right.material.diffuse = 0.7;
    right.material.specular = 0.3;

    var left = Sphere(f32).new();
    try left.setTransform(identity.scale(0.33, 0.33, 0.33).translate(-1.5, 0.33, -0.75));
    left.material.color = Color(f32).new(1.0, 0.8, 0.1);
    left.material.diffuse = 0.7;
    left.material.specular = 0.3;


    var world = World(f32).new(allocator);
    try world.objects.append(floor);
    try world.objects.append(left_wall);
    try world.objects.append(right_wall);
    try world.objects.append(middle);
    try world.objects.append(right);
    try world.objects.append(left);

    try world.lights.append(Light(f32).pointLight(
        Tuple(f32).point(-10.0, 10.0, -10.0), Color(f32).new(1.0, 1.0, 1.0)
    ));

    var camera = Camera(f32).new(1000, 500, pi / 3.0);
    try camera.setTransform(
        Matrix(f32, 4).viewTransform(
            Tuple(f32).point(0.0, 1.5, -5.0), Tuple(f32).point(0.0, 1.0, 0.0), Tuple(f32).vec3(0.0, 1.0, 0.0)
        )
    );

    const canvas = try camera.render(allocator, world);

    const ppm = try canvas.ppm(allocator);

    const file = try std.fs.cwd().createFile(
        "images/simple_world.ppm",
        .{ .read = true },
    );
    defer file.close();

    _ = try file.writeAll(ppm);
}