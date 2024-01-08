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

pub fn renderSimpleWorld() !void {
    const allocator = std.heap.c_allocator;

    const identity = Matrix(f64, 4).identity();

    var floor = Shape(f64).plane();
    floor.material.pattern = Pattern(f64).solid(Color(f64).new(1, 0.9, 0.9));
    floor.material.specular = 0.0;
    floor.material.reflective = 0.5;
    const solid_white = Pattern(f64).solid(Color(f64).new(1.0, 1.0, 1.0));
    const solid_black = Pattern(f64).solid(Color(f64).new(0.0, 0.0, 0.0));
    floor.material.pattern = Pattern(f64).checkers(&solid_white, &solid_black);
    try floor.material.pattern.setTransform(identity.scale(0.1, 0.1, 0.1).rotateY(pi / 4.0));

    var left_wall = Shape(f64).plane();
    try left_wall.setTransform(
        identity
            .rotateX(pi / 2.0)
            .rotateY(-pi / 4.0)
            .translate(0.0, 0.0, 5.0)
    );
    left_wall.material.pattern = Pattern(f64).solid(Color(f64).new(0.9, 1.0, 0.9));
    left_wall.material.specular = 0.0;
    const solid_light_gray = Pattern(f64).solid(Color(f64).new(0.8, 0.8, 0.8));
    const solid_dark_gray = Pattern(f64).solid(Color(f64).new(0.2, 0.2, 0.2));
    const gray_stripes = Pattern(f64).stripes(&solid_light_gray, &solid_dark_gray);
    left_wall.material.pattern = gray_stripes;
    try left_wall.material.pattern.setTransform(
        Matrix(f64, 4).identity().rotateY(pi / 2.0).scale(0.25, 0.25, 0.25)
    );

    var right_wall = Shape(f64).plane();
    try right_wall.setTransform(
        identity
            .rotateX(pi / 2.0)
            .rotateY(pi / 4.0)
            .translate(0.0, 0.0, 5.0)
    );
    right_wall.material.pattern = Pattern(f64).solid(Color(f64).new(0.9, 0.9, 1.0));
    right_wall.material.specular = 0.0;
    right_wall.material.pattern = gray_stripes;
    try right_wall.material.pattern.setTransform(
        Matrix(f64, 4).identity().translate(1.0, 0.0, 0.0).rotateY(pi / 2.0).scale(0.25, 0.25, 0.25)
    );

    var back_wall = Shape(f64).plane();
    try back_wall.setTransform(
        identity
            .rotateX(pi / 2.0)
            .translate(0.0, 0.0, -15.0)
    );
    back_wall.material.pattern = Pattern(f64).solid(Color(f64).new(0.9, 0.9, 1.0));
    back_wall.material.specular = 0.0;
    back_wall.material.pattern = gray_stripes;
    try back_wall.material.pattern.setTransform(
        Matrix(f64, 4).identity().translate(1.0, 0.0, 0.0).rotateY(pi / 2.0).scale(0.25, 0.25, 0.25)
    );

    var middle = Shape(f64).sphere();
    try middle.setTransform(identity.translate(-0.5, 1.0, 0.5));
    middle.material.pattern = Pattern(f64).solid(Color(f64).new(0.1, 1.0, 0.5));
    middle.material.diffuse = 0.7;
    middle.material.specular = 0.3;
    const p1 = Pattern(f64).solid(Color(f64).new(0.33, 0.4, 0.67));
    const p2 = Pattern(f64).solid(Color(f64).new(0.67, 0.6, 0.33));
    var stripes = Pattern(f64).stripes(&p1, &p2);
    try stripes.setTransform(identity.rotateZ(pi / 1.5).scale(0.25, 0.25, 0.25));
    middle.material.pattern = Pattern(f64).perturb(&stripes, .{});

    var right = Shape(f64).sphere();
    try right.setTransform(identity.scale(0.5, 0.5, 0.5).translate(1.5, 0.5, -0.5));
    right.material.pattern = Pattern(f64).solid(Color(f64).new(0.5, 1.0, 0.1));
    right.material.diffuse = 0.7;
    right.material.specular = 0.3;
    const solid_green = Pattern(f64).solid(Color(f64).new(0.0, 1.0, 0.0));
    const solid_red = Pattern(f64).solid(Color(f64).new(1.0, 0.0, 0.0));
    var gradient = Pattern(f64).gradient(&solid_green, &solid_red);
    try gradient.setTransform(identity.translate(-0.5, 0.0, 0.0).scale(2.0, 2.0, 2.0).rotateY(pi / 6.0));
    right.material.pattern = gradient;

    var left = Shape(f64).sphere();
    try left.setTransform(identity.scale(0.33, 0.33, 0.33).translate(-1.5, 0.33, -0.75));
    left.material.pattern = Pattern(f64).solid(Color(f64).new(1.0, 1.0, 1.0));
    left.material.diffuse = 0.7;
    left.material.specular = 0.3;
    left.material.reflective = 0.7;


    var world = World(f64).new(allocator);
    defer world.destroy();
    try world.objects.append(floor);
    try world.objects.append(left_wall);
    try world.objects.append(right_wall);
    try world.objects.append(back_wall);
    try world.objects.append(middle);
    try world.objects.append(right);
    try world.objects.append(left);

    try world.lights.append(Light(f64).pointLight(
        Tuple(f64).point(-10.0, 10.0, -10.0), Color(f64).new(0.5, 0.5, 0.5)
    ));
    try world.lights.append(Light(f64).pointLight(
        Tuple(f64).point(10.0, 10.0, -10.0), Color(f64).new(0.5, 0.5, 0.5)
    ));

    var camera = Camera(f64).new(1000, 500, pi / 3.0);
    try camera.setTransform(
        Matrix(f64, 4).viewTransform(
            Tuple(f64).point(0.0, 1.5, -5.0), Tuple(f64).point(0.0, 1.0, 0.0), Tuple(f64).vec3(0.0, 1.0, 0.0)
        )
    );

    const canvas = try camera.render(allocator, world);
    defer canvas.destroy();

    var image = try canvas.toImage(allocator);
    defer image.deinit();

    try image.writeToFilePath("images" ++ std.fs.path.sep_str ++ "simple_world.png", .{ .png = .{} });
}
