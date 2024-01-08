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

pub fn renderSimpleSuperflat() !void {
    const allocator = std.heap.c_allocator;

    const identity = Matrix(f64, 4).identity();

    var floor = Shape(f64).plane();
    floor.material.pattern = Pattern(f64).solid(Color(f64).new(1, 0.9, 0.9));
    floor.material.specular = 0.0;
    const solid_white = Pattern(f64).solid(Color(f64).new(1.0, 1.0, 1.0));
    const solid_black = Pattern(f64).solid(Color(f64).new(0.0, 0.0, 0.0));
    var white_black_stripes = Pattern(f64).radialGradient(&solid_white, &solid_black);
    try white_black_stripes.setTransform(identity.scale(0.25, 0.25, 0.25).rotateY(pi / 2.0));

    const solid_blue = Pattern(f64).solid(Color(f64).new(0.0, 0.0, 1.0));
    var pattern = Pattern(f64).blend(&white_black_stripes, &solid_blue);
    try pattern.setTransform(identity.translate(-0.5, 0.0, 0.0));
    floor.material.pattern = pattern;

    var large = Shape(f64).sphere();
    try large.setTransform(identity.translate(-0.5, 1.0, 0.5).scale(1.0, 0.5, 1.0));
    large.material.pattern = Pattern(f64).solid(Color(f64).new(0.1, 1.0, 0.5));
    large.material.diffuse = 0.7;
    large.material.specular = 0.3;

    var small = Shape(f64).sphere();
    try small.setTransform(identity.scale(0.5, 0.5, 0.5).translate(1.5, 0.5, -0.5));
    small.material.pattern = Pattern(f64).solid(Color(f64).new(0.5, 1.0, 0.1));
    small.material.diffuse = 0.7;
    small.material.specular = 0.3;

    var tiny = Shape(f64).sphere();
    try tiny.setTransform(
        identity
            .scale(0.25, 0.25, 0.25)
            .translate(1.5, 1.25, -0.5)
    );
    tiny.material.pattern = Pattern(f64).solid(Color(f64).new(1.0, 0.2, 1.0));
    tiny.material.diffuse = 0.7;
    tiny.material.specular = 0.3;


    var world = World(f64).new(allocator);
    defer world.destroy();
    try world.objects.append(floor);
    try world.objects.append(large);
    try world.objects.append(small);
    try world.objects.append(tiny);

    try world.lights.append(Light(f64).pointLight(
        Tuple(f64).point(-10.0, 10.0, -10.0), Color(f64).new(1.0, 1.0, 1.0)
    ));

    var camera = Camera(f64).new(1000, 500, pi / 3.0);
    try camera.setTransform(
        Matrix(f64, 4).viewTransform(
            Tuple(f64).point(0.0, 1.3, -5.0), Tuple(f64).point(1.0, 0.6, 0.0), Tuple(f64).vec3(0.0, 1.0, 0.0)
        )
    );

    const canvas = try camera.render(allocator, world);
    defer canvas.destroy();

    var image = try canvas.toImage(allocator);
    defer image.deinit();

    try image.writeToFilePath("images" ++ std.fs.path.sep_str ++ "simple_superflat.png", .{ .png = .{} });
}
