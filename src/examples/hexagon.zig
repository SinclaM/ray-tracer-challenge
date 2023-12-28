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

fn hexagonCorner(comptime T: type) !Shape(T) {
    var corner = Shape(T).sphere();
    try corner.setTransform(
        Matrix(T, 4)
            .identity()
            .scale(0.25, 0.25, 0.25)
            .translate(0.0, 0.0, -1.0)
    );

    return corner;
}

fn hexagonEdge(comptime T: type) !Shape(T) {
    var edge = Shape(T).cylinder();
    edge.variant.cylinder.min = 0.0;
    edge.variant.cylinder.max = 1.0;

    try edge.setTransform(
        Matrix(T, 4)
            .identity()
            .scale(0.25, 1.0, 0.25)
            .rotateZ(-pi / 2.0)
            .rotateY(-pi / 6.0)
            .translate(0.0, 0.0, -1.0)
    );

    return edge;
}

fn hexagonSide(comptime T: type, allocator: Allocator) !Shape(T) {
    var side = try Shape(T).group(allocator);
    const corner = try hexagonCorner(T);
    const edge = try hexagonEdge(T);

    try side.addChild(corner);
    try side.addChild(edge);

    return side;
}

fn hexagon(comptime T: type, allocator: Allocator) !Shape(T) {
    var hex = try Shape(T).group(allocator);

    for (0..6) |n| {
        var side = try hexagonSide(T, allocator);
        try side.setTransform(Matrix(T, 4).identity().rotateY(@as(T, @floatFromInt(n)) * pi / 3.0));

        try hex.addChild(side);
    }

    return hex;
}


pub fn renderHexagon() !void {
    const allocator = std.heap.raw_c_allocator;

    var hex = try hexagon(f64, allocator);
    defer hex.variant.group.destroy();

    var world = World(f64).new(allocator);
    defer world.destroy();

    try world.objects.append(hex);

    try world.lights.append(Light(f64).pointLight(
        Tuple(f64).point(2.0, 10.0, -5.0), Color(f64).new(0.9, 0.9, 0.9)
    ));

    var camera = Camera(f64).new(500, 500, 0.45);
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
        "images/hexagon.ppm",
        .{ .read = true },
    );
    defer file.close();

    _ = try file.writeAll(ppm);
}

