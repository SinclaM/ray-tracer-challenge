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
    parser.loadObj(obj);
    var teapot = parser.toGroup();

    try teapot.setTransform(
        Matrix(f64, 4)
            .identity()
            .translate(-1.0, -1.0, 0.0)
            .scale(1.3, 1.3, 1.3)
            .rotateY(0.4)
    );

    var world = World(f64).new(allocator);
    defer world.destroy();

    try world.objects.append(teapot.*);

    try world.lights.append(Light(f64).pointLight(
        Tuple(f64).point(2.0, 10.0, -5.0), Color(f64).new(0.9, 0.9, 0.9)
    ));

    var camera = Camera(f64).new(500, 500, 1.5);
    try camera.setTransform(
        Matrix(f64, 4).viewTransform(
            Tuple(f64).point(0.0, 3.0, -5.0), Tuple(f64).point(0.0, 0.0, 0.0), Tuple(f64).vec3(0.0, 1.0, 0.0)
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


