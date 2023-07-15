const std = @import("std");
const testing = std.testing;
const json = std.json;
const Allocator = std.mem.Allocator;

const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Matrix = @import("../raytracer/matrix.zig").Matrix;
const Color = @import("../raytracer/color.zig").Color;
const Shape = @import("../raytracer/shapes/shape.zig").Shape;
const Pattern = @import("../raytracer/patterns/pattern.zig").Pattern;
const Material = @import("../raytracer/material.zig").Material;
const Light = @import("../raytracer/light.zig").Light;
const World = @import("../raytracer/world.zig").World;
const Camera = @import("../raytracer/camera.zig").Camera;

fn CameraConfig(comptime T: type) type {
    return struct {
        width: usize,
        height: usize,
        @"field-of-view": T,
        from: [3]T,
        to: [3]T,
        up: [3]T,
    };
}

fn TransformConfig(comptime T: type) type {
    return []union(enum) {
        translate: *[3]T,
        scale: *[3]T,
        @"rotate-x": *T,
        @"rotate-y": *T,
        @"rotate-z": *T,
        shear: *Matrix(T, 4).ShearArgs,
    };
}

fn PatternConfig(comptime T: type) type {
    return struct {
        @"type": union(enum) {
            solid: *[3]T,
            stripes: [2]*PatternConfig(T),
            rings: [2]*PatternConfig(T),
            gradient: [2]*PatternConfig(T),
            @"radial-gradient": [2]*PatternConfig(T),
            checkers: [2]*PatternConfig(T),
            perturb: *PatternConfig(T),
            blend: [2]*PatternConfig(T),
        },
        transform: ?TransformConfig(T) = null,
    };
}

fn MaterialConfig(comptime T: type) type {
    return struct {
        pattern: PatternConfig(T),
        ambient: T = 0.1,
        diffuse: T = 0.9,
        specular: T = 0.9,
        shininess: T = 200.0,
        reflective: T = 0.0,
        transparency: T = 0.0,
        @"refractive-index": T = 1.0,
    };
}

fn ObjectConfig(comptime T: type) type {
    return struct {
        @"type": union(enum) {
            sphere: void,
            plane: void,
            cube: void,
            cylinder: *struct {
                min: T = -std.math.inf(T),
                max: T = std.math.inf(T),
                closed: bool = false,
            }
        },
        transform: ?TransformConfig(T) = null,
        material: ?MaterialConfig(T) = null,
        @"casts-shadow": bool = true,
    };
}

fn LightConfig(comptime T: type) type {
    return union(enum) {
        @"point-light": *struct {
            position: [3]T,
            intensity: [3]T,
        },
    };
}

fn SceneConfig(comptime T: type) type {
    return struct {
        camera: CameraConfig(T),
        objects: []ObjectConfig(T),
        lights: []LightConfig(T),
    };
}

const SceneParseError = error { UnknownShape };

fn parseTransform(comptime T: type, transform: TransformConfig(T)) Matrix(T, 4) {
    var matrix = Matrix(T, 4).identity();

    for (transform) |t| {
        switch (t) {
            .translate => |buf| {
                matrix = matrix.translate(buf[0], buf[1], buf[2]);
            },
            .scale => |buf| {
                matrix = matrix.scale(buf[0], buf[1], buf[2]);
            },
            .@"rotate-x" => |angle| {
                matrix = matrix.rotateX(angle.*);
            },
            .@"rotate-y" => |angle| {
                matrix = matrix.rotateY(angle.*);
            },
            .@"rotate-z" => |angle| {
                matrix = matrix.rotateZ(angle.*);
            },
            .shear => |args| {
                matrix = matrix.shear(args.*);
            }
        }
    }

    return matrix;
}

fn parsePattern(comptime T: type, allocator: Allocator, pattern: PatternConfig(T)) !Pattern(T) {
    var pat = blk: {
        switch (pattern.@"type") {
            .solid => |buf| {
                break :blk Pattern(T).solid(Color(T).new(buf[0], buf[1], buf[2]));
            },
            .stripes => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, buf[0].*);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, buf[1].*);
                break :blk Pattern(T).stripes(p1, p2);
            },
            .rings => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, buf[0].*);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, buf[1].*);
                break :blk Pattern(T).rings(p1, p2);
            },
            .gradient => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, buf[0].*);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, buf[1].*);
                break :blk Pattern(T).gradient(p1, p2);
            },
            .@"radial-gradient" => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, buf[0].*);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, buf[1].*);
                break :blk Pattern(T).radialGradient(p1, p2);
            },
            .checkers => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, buf[0].*);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, buf[1].*);
                break :blk Pattern(T).checkers(p1, p2);
            },
            .perturb => |p| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, p.*);

                break :blk Pattern(T).perturb(p1, .{});
            },
            .blend => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, buf[0].*);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, buf[1].*);
                break :blk Pattern(T).blend(p1, p2);
            },
        }
    };

    if (pattern.transform) |transform| {
        try pat.setTransform(parseTransform(T, transform));
    }

    return pat;
}

fn parseMaterial(comptime T: type, allocator: Allocator, material: MaterialConfig(T)) !Material(T) {
    var mat = Material(T).new();
    mat.pattern = try parsePattern(T, allocator, material.pattern);
    mat.ambient = material.ambient;
    mat.diffuse = material.diffuse;
    mat.specular = material.specular;
    mat.shininess = material.shininess;
    mat.reflective = material.reflective;
    mat.transparency = material.transparency;
    mat.refractive_index = material.@"refractive-index";

    return mat;
}

fn parseObject(comptime T: type, allocator: Allocator, object: ObjectConfig(T)) !Shape(T) {
    var shape = switch (object.@"type") {
        .sphere => Shape(T).sphere(),
        .plane => Shape(T).plane(),
        .cube => Shape(T).cube(),
        .cylinder => |cyl| blk: {
            var c = Shape(T).cylinder();
            c.variant.cylinder.min = cyl.min;
            c.variant.cylinder.max = cyl.max;
            c.variant.cylinder.closed = cyl.closed;
            break :blk c;
        },
    };

    shape.casts_shadow = object.@"casts-shadow";

    if (object.transform) |transform| {
        try shape.setTransform(parseTransform(T, transform));
    }

    if (object.material) |material| {
        shape.material = try parseMaterial(T, allocator, material);
    }

    return shape;
}

fn parseLight(comptime T: type, light: LightConfig(T)) Light(T) {
    const light_ = blk: {
        switch(light) {
            LightConfig(T).@"point-light" => |l| {
                break :blk Light(T).pointLight(
                    Tuple(T).point(l.position[0], l.position[1], l.position[2]),
                    Color(T).new(l.intensity[0], l.intensity[1], l.intensity[2]),
                );
            }
        }
    };

    return light_;
}

pub fn SceneInfo(comptime T: type) type {
    return struct { camera: Camera(T), world: World(T) };
}

pub fn parseScene(
    comptime T: type, allocator: Allocator, scene_json: []const u8
) !SceneInfo(T) {
    const parsed = try std.json.parseFromSlice(SceneConfig(T), allocator, scene_json, .{});
    defer parsed.deinit();

    var camera = Camera(T).new(
        parsed.value.camera.width, parsed.value.camera.height, parsed.value.camera.@"field-of-view"
    );

    const from = Tuple(T).point(
        parsed.value.camera.from[0], parsed.value.camera.from[1], parsed.value.camera.from[2]
    );

    const to = Tuple(T).point(
        parsed.value.camera.to[0], parsed.value.camera.to[1], parsed.value.camera.to[2]
    );

    const up = Tuple(T).vec3(
        parsed.value.camera.up[0], parsed.value.camera.up[1], parsed.value.camera.up[2]
    );

    try camera.setTransform(Matrix(T, 4).viewTransform(from, to, up));

    var world = World(T).new(allocator);

    for (parsed.value.objects) |object| {
        try world.objects.append(try parseObject(T, allocator, object));
    }

    for (parsed.value.lights) |light| {
        try world.lights.append(parseLight(T, light));
    }

    return .{ .camera = camera, .world = world };
}


test "Simple" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const scene =
        \\ {
        \\     "camera": {
        \\         "width": 1280,
        \\         "height": 1000,
        \\         "field-of-view": 0.785,
        \\         "from": [ -6, 6, -10 ],
        \\         "to": [ 6, 0, 6 ],
        \\         "up": [ -0.45, 1, 0 ]
        \\     },
        \\     "objects": [
        \\         {
        \\             "type": { "sphere": {} },
        \\             "transform": [
        \\                 { "translate": [1.0, 2.0, 3.0] },
        \\                 { "scale": [0.5, 0.5, 0.5] }
        \\             ],
        \\             "material": {
        \\                 "pattern": {
        \\                     "type": {
        \\                         "stripes": [
        \\                             { "type": { "solid": [1.0, 1.0, 1.0] } },
        \\                             { "type": { "solid": [0.0, 0.0, 0.0] } }
        \\                         ]
        \\                      },
        \\                     "transform": [
        \\                         { "scale": [0.1, 0.1, 0.1] }
        \\                     ]
        \\                 },
        \\                 "reflective": 0.5
        \\             }
        \\         }
        \\     ],
        \\     "lights": [
        \\         {
        \\             "point-light": {
        \\                 "position": [-10.0, 10.0, -10.0],
        \\                 "intensity": [1.0, 1.0, 1.0]
        \\             }
        \\         }
        \\     ]
        \\ }
        \\ 
    ;

    const scene_info = try parseScene(f32, allocator, scene);
    const camera = &scene_info.camera;
    const world = &scene_info.world;
    defer world.destroy();

    var expected_camera = Camera(f32).new(1280, 1000, 0.785);
    try expected_camera.setTransform(
        Matrix(f32, 4).viewTransform(
            Tuple(f32).point(-6.0, 6.0, -10.0),
            Tuple(f32).point(6.0, 0.0, 6.0),
            Tuple(f32).vec3(-0.45, 1.0, 0.0)
        )
    );

    try testing.expectEqual(camera.*, expected_camera);

    var expected_object = Shape(f32).sphere();
    try expected_object.setTransform(
        Matrix(f32, 4).identity().translate(1.0, 2.0, 3.0).scale(0.5, 0.5, 0.5)
    );
    const solid_white = Pattern(f32).solid(Color(f32).new(1.0, 1.0, 1.0));
    const solid_black = Pattern(f32).solid(Color(f32).new(0.0, 0.0, 0.0));
    expected_object.material.pattern = Pattern(f32).stripes(&solid_white, &solid_black);
    try expected_object.material.pattern.setTransform(
        Matrix(f32, 4).identity().scale(0.1, 0.1, 0.1)
    );
    expected_object.material.reflective = 0.5;

    try testing.expectEqual(world.objects.items.len, 1);

    const object = world.objects.items[0];
    try testing.expectEqual(
        object.material.pattern._transform,
        expected_object.material.pattern._transform
    );
    try testing.expectEqual(
        object.material.pattern._inverse_transform,
        expected_object.material.pattern._inverse_transform
    );
    try testing.expectEqual(
        object.material.ambient,
        expected_object.material.ambient
    );
    try testing.expectEqual(
        object.material.reflective,
        expected_object.material.reflective
    );
    try testing.expectEqual(
        object.material.pattern.variant.stripes.a.*,
        expected_object.material.pattern.variant.stripes.a.*
    );
    try testing.expectEqual(
        object.material.pattern.variant.stripes.b.*,
        expected_object.material.pattern.variant.stripes.b.*
    );

    const expected_light = Light(f32).pointLight(
        Tuple(f32).point(-10.0, 10.0, -10.0), Color(f32).new(1.0, 1.0, 1.0)
    );

    try testing.expectEqual(world.lights.items.len, 1);
    try testing.expectEqual(world.lights.items[0], expected_light);
}
