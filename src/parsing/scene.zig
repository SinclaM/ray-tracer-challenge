const target = @import("builtin").target;

const std = @import("std");
const testing = std.testing;
const json = std.json;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Matrix = @import("../raytracer/matrix.zig").Matrix;
const Color = @import("../raytracer/color.zig").Color;
const Shape = @import("../raytracer/shapes/shape.zig").Shape;
const TextureMap = @import("../raytracer/patterns/texture_map.zig").TextureMap;
const UvPattern = @import("../raytracer/patterns/texture_map.zig").UvPattern;
const Pattern = @import("../raytracer/patterns/pattern.zig").Pattern;
const Material = @import("../raytracer/material.zig").Material;
const Light = @import("../raytracer/light.zig").Light;
const World = @import("../raytracer/world.zig").World;
const Camera = @import("../raytracer/camera.zig").Camera;
const Canvas = @import("../raytracer/canvas.zig").Canvas;

const ObjParser = @import("obj.zig").ObjParser;

fn ObjectDefinitionConfig(comptime T: type) type {
    return struct {
        name: []const u8,
        value: ObjectConfig(T),
    };
}

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

fn UvPatternConfig(comptime T: type) type {
    return union(enum) {
        @"align-check": struct {
            central: *PatternConfig(T),
            @"upper-left": *PatternConfig(T),
            @"upper-right": *PatternConfig(T),
            @"bottom-left": *PatternConfig(T),
            @"bottom-right": *PatternConfig(T),
        },
        checkers: struct {
            width: T,
            height: T,
            patterns: [2]*PatternConfig(T),
        },
        image: struct {
            file: []const u8,
        },
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
            @"texture-map": *union(enum) {
                spherical: struct { @"uv-pattern": UvPatternConfig(T) },
                planar: struct { @"uv-pattern": UvPatternConfig(T) },
                cylindrical: struct { @"uv-pattern": UvPatternConfig(T) },
                cubic: struct {
                    front: UvPatternConfig(T),
                    back: UvPatternConfig(T),
                    left: UvPatternConfig(T),
                    right: UvPatternConfig(T),
                    up: UvPatternConfig(T),
                    down: UvPatternConfig(T),
                }
            },
        },
        transform: ?TransformConfig(T) = null,
    };
}

fn MaterialConfig(comptime T: type) type {
    return struct {
        pattern: ?PatternConfig(T) = null,
        ambient: ?T = null,
        diffuse: ?T = null,
        specular: ?T = null,
        shininess: ?T = null,
        reflective: ?T = null,
        transparency: ?T = null,
        @"refractive-index": ?T = null,
    };
}

fn ObjectConfig(comptime T: type) type {
    return struct {
        @"type": union(enum) {
            @"from-definition": []const u8,
            @"from-obj": *struct {
                file: []const u8,
                normalize: bool = true
            },
            sphere: void,
            cube: void,
            cylinder: *struct {
                min: T = -std.math.inf(T),
                max: T = std.math.inf(T),
                closed: bool = false,
            },
            cone: *struct {
                min: T = -std.math.inf(T),
                max: T = std.math.inf(T),
                closed: bool = false,
            },
            triangle: *struct {
                p1: [3]T,
                p2: [3]T,
                p3: [3]T,
            },
            plane: void,
            group: []ObjectConfig(T),
        },
        transform: ?TransformConfig(T) = null,
        material: ?MaterialConfig(T) = null,
        @"casts-shadow": ?bool = null,

        const Self = @This();
        const Info = struct {
            material: ?Material(T),
            transform: Matrix(T, 4),
            casts_shadow: ?bool
        };

        fn inherit(
            object: Self,
            allocator: Allocator,
            arena_allocator: Allocator,
            inherited: InheritedState(T),
            load_file_data: *const fn (allocator: Allocator, file_name: []const u8) anyerror![]const u8
        ) !Info {
            const material = if (object.material) |mat| blk: {
                break :blk try parseMaterial(T, allocator, arena_allocator, mat, inherited.material, load_file_data);
            } else blk: {
                break :blk inherited.material;
            };

            const transform = if (object.transform) |t| blk: {
                break :blk parseTransform(T, t).mul(inherited.transform);
            } else blk: {
                break :blk inherited.transform;
            };

            const casts_shadow = if (object.@"casts-shadow") |shadow| blk: {
                break :blk shadow;
            } else blk: {
                break :blk inherited.casts_shadow;
            };

            return .{ .material = material, .transform = transform, .casts_shadow = casts_shadow };
        }
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
        @"shape-definitions": []ObjectDefinitionConfig(T) = &.{},
        camera: CameraConfig(T),
        lights: []LightConfig(T),
        objects: []ObjectConfig(T),
    };
}

const SceneParseError = error { UnknownShape, UnknownDefinition, UnknownMapping };

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

fn parseUvPattern(
    comptime T: type,
    allocator: Allocator,
    arena_allocator: Allocator,
    uv_pattern: UvPatternConfig(T),
    load_file_data: *const fn (allocator: Allocator, file_name: []const u8) anyerror![]const u8
) !UvPattern(T) {
    const uv_pat = blk: {
        switch (uv_pattern) {
            .@"align-check" => |align_check| {
                const central = try allocator.create(Pattern(T));
                central.* = try parsePattern(T, allocator, arena_allocator, align_check.central.*, load_file_data);

                const ul = try allocator.create(Pattern(T));
                ul.* = try parsePattern(T, allocator, arena_allocator, align_check.@"upper-left".*, load_file_data);

                const ur = try allocator.create(Pattern(T));
                ur.* = try parsePattern(T, allocator, arena_allocator, align_check.@"upper-right".*, load_file_data);

                const bl = try allocator.create(Pattern(T));
                bl.* = try parsePattern(T, allocator, arena_allocator, align_check.@"bottom-left".*, load_file_data);

                const br = try allocator.create(Pattern(T));
                br.* = try parsePattern(T, allocator, arena_allocator, align_check.@"bottom-right".*, load_file_data);

                break :blk UvPattern(T).uvAlignCheck(central, ul, ur, bl, br);
            },
            .checkers => |c| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, arena_allocator, c.patterns[0].*, load_file_data);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, arena_allocator, c.patterns[1].*, load_file_data);
                break :blk UvPattern(T).uvCheckers(c.width, c.height, p1, p2);
            },
            .image => |image| {
                const ppm = try load_file_data(allocator, image.file);
                defer allocator.free(ppm);

                const canvas = try Canvas(T).from_ppm(arena_allocator, ppm);
                break :blk UvPattern(T).uvImage(canvas);
            },
        }
    };

    return uv_pat;
}

fn parsePattern(
    comptime T: type,
    allocator: Allocator,
    arena_allocator: Allocator,
    pattern: PatternConfig(T),
    load_file_data: *const fn (allocator: Allocator, file_name: []const u8) anyerror![]const u8
) anyerror!Pattern(T) {
    var pat = blk: {
        switch (pattern.@"type") {
            .solid => |buf| {
                break :blk Pattern(T).solid(Color(T).new(buf[0], buf[1], buf[2]));
            },
            .stripes => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, arena_allocator, buf[0].*, load_file_data);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, arena_allocator, buf[1].*, load_file_data);
                break :blk Pattern(T).stripes(p1, p2);
            },
            .rings => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, arena_allocator, buf[0].*, load_file_data);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, arena_allocator, buf[1].*, load_file_data);
                break :blk Pattern(T).rings(p1, p2);
            },
            .gradient => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, arena_allocator, buf[0].*, load_file_data);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, arena_allocator, buf[1].*, load_file_data);
                break :blk Pattern(T).gradient(p1, p2);
            },
            .@"radial-gradient" => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, arena_allocator, buf[0].*, load_file_data);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, arena_allocator, buf[1].*, load_file_data);
                break :blk Pattern(T).radialGradient(p1, p2);
            },
            .checkers => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, arena_allocator, buf[0].*, load_file_data);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, arena_allocator, buf[1].*, load_file_data);
                break :blk Pattern(T).checkers(p1, p2);
            },
            .perturb => |p| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, arena_allocator, p.*, load_file_data);

                break :blk Pattern(T).perturb(p1, .{});
            },
            .blend => |buf| {
                const p1 = try allocator.create(Pattern(T));
                p1.* = try parsePattern(T, allocator, arena_allocator, buf[0].*, load_file_data);

                const p2 = try allocator.create(Pattern(T));
                p2.* = try parsePattern(T, allocator, arena_allocator, buf[1].*, load_file_data);
                break :blk Pattern(T).blend(p1, p2);
            },
            .@"texture-map" => |texture_map| {
                switch (texture_map.*) {
                    .spherical => |spherical| {
                        const uv_pattern = try parseUvPattern(
                            T, allocator, arena_allocator, spherical.@"uv-pattern", load_file_data
                        );
                        break :blk Pattern(T).textureMap(TextureMap(T).spherical(uv_pattern));
                    },
                    .planar => |planar| {
                        const uv_pattern = try parseUvPattern(
                            T, allocator, arena_allocator, planar.@"uv-pattern", load_file_data
                        );
                        break :blk Pattern(T).textureMap(TextureMap(T).planar(uv_pattern));
                    },
                    .cylindrical => |cylindrical| {
                        const uv_pattern = try parseUvPattern(
                            T, allocator, arena_allocator, cylindrical.@"uv-pattern", load_file_data
                        );
                        break :blk Pattern(T).textureMap(TextureMap(T).cylindrical(uv_pattern));
                    },
                    .cubic => |cubic| {
                        const front = try parseUvPattern(T, allocator, arena_allocator, cubic.front, load_file_data);
                        const back = try parseUvPattern(T, allocator, arena_allocator, cubic.back, load_file_data);
                        const left = try parseUvPattern(T, allocator, arena_allocator, cubic.left, load_file_data);
                        const right = try parseUvPattern(T, allocator, arena_allocator, cubic.right, load_file_data);
                        const up = try parseUvPattern(T, allocator, arena_allocator, cubic.up, load_file_data);
                        const down = try parseUvPattern(T, allocator, arena_allocator, cubic.down, load_file_data);
                        break :blk Pattern(T).textureMap(TextureMap(T).cubic(front, back, left, right, up, down));
                    },
                }
            },
        }
    };

    if (pattern.transform) |transform| {
        try pat.setTransform(parseTransform(T, transform));
    }

    return pat;
}

fn parseMaterial(
    comptime T: type,
    allocator: Allocator,
    arena_allocator: Allocator,
    material: MaterialConfig(T),
    inherited_material: ?Material(T),
    load_file_data: *const fn (allocator: Allocator, file_name: []const u8) anyerror![]const u8
) !Material(T) {
    var mat = inherited_material orelse Material(T).new();

    if (material.pattern) |pattern| {
        mat.pattern = try parsePattern(T, allocator, arena_allocator, pattern, load_file_data);
    }

    mat.ambient = material.ambient orelse mat.ambient;
    mat.diffuse = material.diffuse orelse mat.diffuse;
    mat.specular = material.specular orelse mat.specular;
    mat.shininess = material.shininess orelse mat.shininess;
    mat.reflective = material.reflective orelse mat.reflective;
    mat.transparency = material.transparency orelse mat.transparency;
    mat.refractive_index = material.@"refractive-index" orelse mat.refractive_index;

    return mat;
}

pub fn InheritedState(comptime T: type) type {
    return struct {
        material: ?Material(T) = null,
        transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        casts_shadow: ?bool = null,
    };
}

fn parseObject(
    comptime T: type,
    allocator: Allocator,
    arena_allocator: Allocator,
    object: ObjectConfig(T),
    inherited: InheritedState(T),
    definitions: StringHashMap(ObjectDefinitionConfig(T)),
    load_file_data: *const fn (allocator: Allocator, file_name: []const u8) anyerror![]const u8
) !Shape(T) {
    const info = try object.inherit(allocator, arena_allocator, inherited, load_file_data);
    var material = info.material;
    var transform = info.transform;
    var casts_shadow = info.casts_shadow;

    var shape = switch (object.@"type") {
        .@"from-definition" => |name| blk: {
            if (definitions.get(name)) |def| {
                // We need to parse the given definition in such a way that
                // transformations provided for this `object` are applied
                // after both any transformations being currently inherited
                // (i.e. `inherited.transform`) and those that will be discovered
                // by parsing the referred-to definition.
                //
                // However, we must also pass along material and shadow casting
                // information differently, because those fields override the
                // ones we may find in the definition, rather than extending
                // them.
                //
                // TODO: this is horrifying and almost certainly buggy.
                const parent = try parseObject(
                    T,
                    allocator,
                    arena_allocator,
                    def.value,
                    .{ .material = material, .transform = inherited.transform, .casts_shadow = casts_shadow},
                    definitions,
                    load_file_data
                );
                const parent_state = .{
                    .material = parent.material,
                    .transform = parent._transform,
                    .casts_shadow = parent.casts_shadow
                };

                const new = try object.inherit(allocator, arena_allocator, parent_state, load_file_data);
                material = new.material;
                transform = new.transform;
                casts_shadow = new.casts_shadow;
                break :blk parent;
            } else {
                return SceneParseError.UnknownDefinition;
            }
        },
        .@"from-obj" => |from| blk: {
            const obj = try load_file_data(allocator, from.file);
            defer allocator.free(obj);

            var parser = try ObjParser(T).new(allocator);
            defer parser.destroy();

            parser.loadObj(obj, .{ .material = material, .casts_shadow = casts_shadow }, from.normalize);

            break :blk parser.toGroup();
        },
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
        .cone => |cone| blk: {
            var c  = Shape(T).cone();
            c.variant.cone.min = cone.min;
            c.variant.cone.max = cone.max;
            c.variant.cone.closed = cone.closed;
            break :blk c;
        },
        .triangle => |tri|
            Shape(T).triangle(
                Tuple(T).point(tri.p1[0], tri.p1[1], tri.p1[2]),
                Tuple(T).point(tri.p2[0], tri.p2[1], tri.p2[2]),
                Tuple(T).point(tri.p3[0], tri.p3[1], tri.p3[2])
            ),
        .group => |children| blk: {
            var g = try Shape(T).group(allocator);

            for (children) |child| {
                // Groups will push their own transforms to their children when `setTransform`
                // is called. We should not pass it as inherited state here.
                var s = try parseObject(
                    T,
                    allocator,
                    arena_allocator,
                    child,
                    .{ .material = material, .casts_shadow = casts_shadow},
                    definitions,
                    load_file_data
                );
                try g.addChild(s);
            }

            break :blk g;
        }
    };

    try shape.setTransform(transform);

    if (material) |mat| {
        shape.material = mat;
    }

    if (casts_shadow) |shadow| {
        shape.casts_shadow = shadow;
    }

    try shape.divide(allocator, 8);

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
    comptime T: type,
    arena_allocator: Allocator,
    allocator: Allocator,
    scene_json: []const u8,
    load_file_data: *const fn (allocator: Allocator, file_name: []const u8) anyerror![]const u8
) !SceneInfo(T) {
    const parsed = try std.json.parseFromSlice(SceneConfig(T), arena_allocator, scene_json, .{});
    defer parsed.deinit();

    var definitions = StringHashMap(ObjectDefinitionConfig(T)).init(arena_allocator);
    defer definitions.deinit();

    for (parsed.value.@"shape-definitions") |definition| {
        try definitions.put(definition.name, definition);
    }

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
    camera._saved_from_to_up = [_]Tuple(T) { from, to, up };

    try camera.setTransform(Matrix(T, 4).viewTransform(from, to, up));

    var world = World(T).new(arena_allocator);

    for (parsed.value.objects) |object| {
        try world.objects.append(
            try parseObject(T, allocator, arena_allocator, object, .{}, definitions, load_file_data)
        );
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

    const scene_info = try parseScene(f32, allocator, allocator, scene, undefined);
    const camera = &scene_info.camera;
    const world = &scene_info.world;
    defer world.destroy();

    var expected_camera = Camera(f32).new(1280, 1000, 0.785);
    const from = Tuple(f32).point(-6.0, 6.0, -10.0);
    const to = Tuple(f32).point(6.0, 0.0, 6.0);
    const up = Tuple(f32).vec3(-0.45, 1.0, 0.0);
    try expected_camera.setTransform( Matrix(f32, 4).viewTransform(from, to, up));
    expected_camera._saved_from_to_up = [_]Tuple(f32) { from, to, up };

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
