const std = @import("std");
const pi = std.math.pi;
const Allocator = std.mem.Allocator;

const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Matrix = @import("../raytracer/matrix.zig").Matrix;
const Color = @import("../raytracer/color.zig").Color;
const Material = @import("../raytracer/material.zig").Material;
const Shape = @import("../raytracer/shapes/shape.zig").Shape;
const Light = @import("../raytracer/light.zig").Light;
const World = @import("../raytracer/world.zig").World;
const Camera = @import("../raytracer/camera.zig").Camera;
const Pattern = @import("../raytracer/patterns/pattern.zig").Pattern;
const ObjParser = @import("../parsing/obj.zig").ObjParser;

pub fn renderTeapot() !void {
    const allocator = std.heap.raw_c_allocator;

    const list_allocator = allocator;
    var shape_arena = std.heap.ArenaAllocator.init(allocator);
    defer shape_arena.deinit();
    const shape_allocator = shape_arena.allocator();

    const obj = try std.fs.cwd().readFileAlloc(
        allocator, "obj/teapot.obj", std.math.pow(usize, 2, 20)
    );
    defer allocator.free(obj);

    var parser = try ObjParser(f64).new(list_allocator, shape_allocator);
    defer parser.destroy();
    var material = Material(f64).new();
    material.pattern = Pattern(f64).solid(Color(f64).new(0.8, 0.33, 0.0));
    material.specular = 0.4;
    material.shininess = 100.0;
    parser.loadObj(obj, material);
    var teapot = parser.toGroup();

    try teapot.setTransform(
        Matrix(f64, 4)
            .identity()
            .translate(0.0, 1.0, 0.0)
            .scale(0.7, 0.7, 0.7)
            .rotateY(-0.4)
    );

    var box = Shape(f64).cube();
    try box.setTransform(
        Matrix(f64, 4)
            .identity()
            .translate(0.0, 1.0, 0.0)
            .scale(10.0, 10.0, 10.0)
    );

    const solid_white = Pattern(f64).solid(Color(f64).new(0.55, 0.55, 0.55));
    const solid_black = Pattern(f64).solid(Color(f64).new(0.45, 0.45, 0.45));
    box.material.specular = 0.0;
    box.material.ambient = 0.5;
    box.material.pattern = Pattern(f64).checkers(&solid_white, &solid_black);
    try box.material.pattern.setTransform(
        Matrix(f64, 4)
            .identity()
            .scale(0.025, 0.025, 0.025)
    );

    var world = World(f64).new(allocator);
    defer world.destroy();

    try world.objects.append(teapot.*);
    try world.objects.append(box);

    try world.lights.append(Light(f64).pointLight(
        Tuple(f64).point(2.0, 6.0, -6.0), Color(f64).new(1.0, 1.0, 1.0)
    ));

    var camera = Camera(f64).new(250, 150, 1.0);
    try camera.setTransform(
        Matrix(f64, 4).viewTransform(
            Tuple(f64).point(0.0, 4.0, -4.5), Tuple(f64).point(0.0, 2.0, 0.0), Tuple(f64).vec3(0.0, 1.0, 0.0)
        )
    );

    const canvas = try camera.render(allocator, world);
    defer canvas.destroy();

    const ppm = try canvas.ppm(allocator);
    defer allocator.free(ppm);

    const file = try std.fs.cwd().createFile(
        "images/teapot.ppm",
        .{ .read = true },
    );
    defer file.close();

    _ = try file.writeAll(ppm);
}


