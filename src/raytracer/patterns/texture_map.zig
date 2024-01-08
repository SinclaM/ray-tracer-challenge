const std = @import("std");
const testing = std.testing;

const Tuple = @import("../tuple.zig").Tuple;
const Color = @import("../color.zig").Color;
const Pattern = @import("pattern.zig").Pattern;
const Canvas = @import("../canvas.zig").Canvas;

fn UvTestPattern(comptime T: type) type {
    return struct {
        const Self = @This();

        fn uvPatternAt(self: Self, u: T, v: T, object_point: Tuple(T)) Color(T) {
            _ = .{ self, object_point };

            return Color(T).new(u, v, 0.0);
        }
    };
}

fn UvAlignCheck(comptime T: type) type {
    return struct {
        const Self = @This();

        central: *const Pattern(T),
        upper_left: *const Pattern(T),
        upper_right: *const Pattern(T),
        bottom_left: *const Pattern(T),
        bottom_right: *const Pattern(T),

        fn uvPatternAt(self: Self, u: T, v: T, object_point: Tuple(T)) Color(T) {
            if (v > 0.8) {
                if (u < 0.2) { return self.upper_left.patternAt(object_point); }
                if (u > 0.8) { return self.upper_right.patternAt(object_point); }
            } else if (v < 0.2) {
                if (u < 0.2) { return self.bottom_left.patternAt(object_point); }
                if (u > 0.8) { return self.bottom_right.patternAt(object_point); }
            }
            return self.central.patternAt(object_point);
        }
    };
}

fn UvCheckers(comptime T: type) type {
    return struct {
        const Self = @This();

        width: T,
        height: T,
        a: *const Pattern(T),
        b: *const Pattern(T),

        fn uvPatternAt(self: Self, u: T, v: T, object_point: Tuple(T)) Color(T) {
            const u_adj = @floor(u * self.width);
            const v_adj = @floor(v * self.height);
            if (@mod(u_adj + v_adj, 2.0) < 1.0) {
                return self.a.patternAt(object_point);
            } else {
                return self.b.patternAt(object_point);
            }
        }
    };
}

fn UvImage(comptime T: type) type {
    return struct {
        const Self = @This();

        canvas: Canvas(T),

        fn uvPatternAt(self: Self, u: T, v: T, object_point: Tuple(T)) Color(T) {
            _ = object_point;

            const v_flip = 1.0 - v;

            const x = u * @as(T, @floatFromInt(self.canvas.width - 1));
            const y = v_flip * @as(T, @floatFromInt(self.canvas.height - 1));

            return self.canvas.getPixelPointer(@intFromFloat(@round(x)), @intFromFloat(@round(y))).?.*;
        }
    };
}

pub fn UvPattern(comptime T: type) type {
    return struct {
        const Self = @This();

        variant: union(enum) {
            uv_align_check: UvAlignCheck(T),
            uv_checkers: UvCheckers(T),
            uv_test_pattern: UvTestPattern(T),
            uv_image: UvImage(T),
        },

        pub fn uvTestPattern() Self {
            return .{ .variant = .{ .uv_test_pattern = .{} } };
        }

        pub fn uvAlignCheck(
            central: *const Pattern(T),
            upper_left: *const Pattern(T),
            upper_right: *const Pattern(T),
            bottom_left: *const Pattern(T),
            bottom_right: *const Pattern(T)
        ) Self {
            return .{
                .variant = .{
                    .uv_align_check = .{
                        .central = central,
                        .upper_left = upper_left,
                        .upper_right = upper_right,
                        .bottom_left = bottom_left,
                        .bottom_right = bottom_right
                    }
                }
            };
        }

        pub fn uvCheckers(width: T, height: T, a: *const Pattern(T), b: *const Pattern(T)) Self {
            return .{
                .variant = .{
                    .uv_checkers = .{ .width = width, .height = height, .a = a, .b = b }
                }
            };
        }

        pub fn uvImage(canvas: Canvas(T)) Self {
            return .{ .variant = .{ .uv_image = .{ .canvas = canvas } } };
        }

        fn uvPatternAt(self: Self, u: T, v: T, object_point: Tuple(T)) Color(T) {
            const Tag = @typeInfo(@TypeOf(self.variant)).Union.tag_type.?;
            inline for (@typeInfo(Tag).Enum.fields) |field| {
                if (field.value == @intFromEnum(self.variant)) {
                    return @field(self.variant, field.name).uvPatternAt(u, v, object_point);
                }
            }

            unreachable;
        }
    };
}

pub fn TextureMap(comptime T: type) type {
    return union(enum) {
        const Self = @This();

        const Spherical = struct {
            uv_pattern: UvPattern(T),

            pub fn patternAt(self: @This(), pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
                const theta = std.math.atan2(T, pattern_point.x, pattern_point.z);

                const vec = Tuple(T).vec3(pattern_point.x, pattern_point.y, pattern_point.z);
                const radius = vec.magnitude();

                const phi = std.math.acos(pattern_point.y / radius);

                const raw_u = theta / (2.0 * std.math.pi);

                const u = 1 - (raw_u + 0.5);

                const v = 1 - phi / std.math.pi;

                return self.uv_pattern.uvPatternAt(u, v, object_point);
            }
        };

        const Planar = struct {
            uv_pattern: UvPattern(T),

            pub fn patternAt(self: @This(), pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
                const u = @mod(pattern_point.x, 1);
                const v = @mod(pattern_point.z, 1);
                return self.uv_pattern.uvPatternAt(u, v, object_point);
            }
        };

        const Cylindrical = struct {
            uv_pattern: UvPattern(T),

            pub fn patternAt(self: @This(), pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
                const theta = std.math.atan2(T, pattern_point.x, pattern_point.z);
                const raw_u = theta / (2.0 * std.math.pi);
                const u = 1.0 - (raw_u + 0.5);

                const v = @mod(pattern_point.y, 1.0);
                return self.uv_pattern.uvPatternAt(u, v, object_point);
            }
        };

        const Cubic = struct {
            const Face = enum(u3) { front, back, left, right, up, down };

            fn faceFromPoint(point: Tuple(T)) Face {
                const abs_x = @abs(point.x);
                const abs_y = @abs(point.y);
                const abs_z = @abs(point.z);
                const coord = @max(abs_x, @max(abs_y, abs_z));

                if (coord == point.x)  { return Face.right; }
                if (coord == -point.x) { return Face.left;  }
                if (coord == point.y)  { return Face.up;    }
                if (coord == -point.y) { return Face.down;  }
                if (coord == point.z)  { return Face.front; }

                return Face.back;
            }

            fn uvFront(point: Tuple(T)) [2]T {
                const u = @mod(point.x + 1.0, 2.0) / 2.0;
                const v = @mod(point.y + 1.0, 2.0) / 2.0;

                return [_]T { u, v };
            }

            fn uvBack(point: Tuple(T)) [2]T {
                const u = @mod(1.0 - point.x, 2.0) / 2.0;
                const v = @mod(point.y + 1.0, 2.0) / 2.0;

                return [_]T { u, v };
            }

            fn uvLeft(point: Tuple(T)) [2]T {
                const u = @mod(point.z + 1.0, 2.0) / 2.0;
                const v = @mod(point.y + 1.0, 2.0) / 2.0;

                return [_]T { u, v };
            }

            fn uvRight(point: Tuple(T)) [2]T {
                const u = @mod(1.0 - point.z, 2.0) / 2.0;
                const v = @mod(point.y + 1.0, 2.0) / 2.0;

                return [_]T { u, v };
            }

            fn uvUp(point: Tuple(T)) [2]T {
                const u = @mod(point.x + 1.0, 2.0) / 2.0;
                const v = @mod(1.0 - point.z, 2.0) / 2.0;

                return [_]T { u, v };
            }

            fn uvDown(point: Tuple(T)) [2]T {
                const u = @mod(point.x + 1.0, 2.0) / 2.0;
                const v = @mod(point.z + 1.0, 2.0) / 2.0;

                return [_]T { u, v };
            }

            face_patterns: [6]UvPattern(T),

            pub fn patternAt(self: @This(), pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
                const face = @This().faceFromPoint(pattern_point);

                const uv = switch (face) {
                    .left  => @This().uvLeft(pattern_point),
                    .right => @This().uvRight(pattern_point),
                    .front => @This().uvFront(pattern_point),
                    .back  => @This().uvBack(pattern_point),
                    .up    => @This().uvUp(pattern_point),
                    .down  => @This().uvDown(pattern_point)
                };

                return self.face_patterns[@intFromEnum(face)].uvPatternAt(uv[0], uv[1], object_point);
            }

        };

        spherical: Spherical,
        planar: Planar,
        cylindrical: Cylindrical,
        cubic: Cubic,

        pub fn spherical(uv_pattern: UvPattern(T)) Self {
            return .{ .spherical = .{ .uv_pattern = uv_pattern } };
        }

        pub fn planar(uv_pattern: UvPattern(T)) Self {
            return .{ .planar = .{ .uv_pattern = uv_pattern } };
        }

        pub fn cylindrical(uv_pattern: UvPattern(T)) Self {
            return .{ .cylindrical = .{ .uv_pattern = uv_pattern } };
        }

        pub fn cubic(
            front: UvPattern(T),
            back: UvPattern(T),
            left: UvPattern(T),
            right: UvPattern(T),
            up: UvPattern(T),
            down: UvPattern(T),
        ) Self {
            return .{
                .cubic = .{ .face_patterns = [_]UvPattern(T) { front, back, left, right, up, down } }
            };
        }

        pub fn patternAt(self: Self, pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
            const Tag = @typeInfo(@TypeOf(self)).Union.tag_type.?;
            inline for (@typeInfo(Tag).Enum.fields) |field| {
                if (field.value == @intFromEnum(self)) {
                    return @field(self, field.name).patternAt(pattern_point, object_point);
                }
            }

            unreachable;
        }
    };
}

fn testCheckerPatternIn2D(
    comptime T: type,
    u: T,
    v: T,
    solid_black: *const Pattern(T),
    solid_white: *const Pattern(T),
    expected: Color(T)
) !void {
    const checkers = UvPattern(T).uvCheckers(2, 2, solid_black, solid_white);
    const color = checkers.uvPatternAt(u, v, undefined);
    try testing.expect(color.approxEqual(expected));
}

test "Checker pattern in 2D" {
    const white = Color(f32).new(1.0, 1.0, 1.0);
    const black = Color(f32).new(0.0, 0.0, 0.0);
    const solid_black = Pattern(f32).solid(black);
    const solid_white = Pattern(f32).solid(white);

    try testCheckerPatternIn2D(f32, 0.0, 0.0, &solid_black, &solid_white, black);
    try testCheckerPatternIn2D(f32, 0.5, 0.0, &solid_black, &solid_white, white);
    try testCheckerPatternIn2D(f32, 0.0, 0.5, &solid_black, &solid_white, white);
    try testCheckerPatternIn2D(f32, 0.5, 0.5, &solid_black, &solid_white, black);
    try testCheckerPatternIn2D(f32, 1.0, 1.0, &solid_black, &solid_white, black);
}

fn testMapping(comptime T: type, map: TextureMap(T), point: Tuple(T), u: T, v: T) !void {
    const tolerance = 1e-5;

    const color = map.patternAt(point, undefined);
    try testing.expectApproxEqAbs(u, color.r, tolerance);
    try testing.expectApproxEqAbs(v, color.g, tolerance);
}

test "Using a spherical mapping on a 3D point" {
    const test_pattern = UvPattern(f32).uvTestPattern();
    const map = TextureMap(f32).spherical(test_pattern);

    try testMapping(f32, map, Tuple(f32).point(0, 0, -1), 0.0, 0.5);
    try testMapping(f32, map, Tuple(f32).point(1, 0, 0), 0.25, 0.5);
    try testMapping(f32, map, Tuple(f32).point(0, 0, 1), 0.5, 0.5);
    try testMapping(f32, map, Tuple(f32).point(-1, 0, 0), 0.75, 0.5);
    try testMapping(f32, map, Tuple(f32).point(0, 1, 0), 0.5, 1.0);
    try testMapping(f32, map, Tuple(f32).point(0, -1, 0), 0.5, 0.0);
    try testMapping(f32, map, Tuple(f32).point(1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0), 0), 0.25, 0.75);
}

test "Using a planar mapping on a 3D point" {
    const test_pattern = UvPattern(f32).uvTestPattern();
    const map = TextureMap(f32).planar(test_pattern);

    try testMapping(f32, map, Tuple(f32).point(0.25, 0, 0.5), 0.25, 0.5);
    try testMapping(f32, map, Tuple(f32).point(0.25, 0, -0.25), 0.25, 0.75);
    try testMapping(f32, map, Tuple(f32).point(0.25, 0.5, -0.25), 0.25, 0.75);
    try testMapping(f32, map, Tuple(f32).point(1.25, 0, 0.5), 0.25, 0.5);
    try testMapping(f32, map, Tuple(f32).point(0.25, 0, -1.75), 0.25, 0.25);
    try testMapping(f32, map, Tuple(f32).point(1, 0, -1), 0.0, 0.0);
    try testMapping(f32, map, Tuple(f32).point(0, 0, 0), 0.0, 0.0);
}

test "Using a cylindrical mapping on a 3D point" {
    const test_pattern = UvPattern(f32).uvTestPattern();
    const map = TextureMap(f32).cylindrical(test_pattern);

    try testMapping(f32, map, Tuple(f32).point(0, 0, -1), 0.0, 0.0);
    try testMapping(f32, map, Tuple(f32).point(0, 0.5, -1), 0.0, 0.5);
    try testMapping(f32, map, Tuple(f32).point(0, 1, -1), 0.0, 0.0);
    try testMapping(f32, map, Tuple(f32).point(0.70711, 0.5, -0.70711), 0.125, 0.5);
    try testMapping(f32, map, Tuple(f32).point(1, 0.5, 0), 0.25, 0.5);
    try testMapping(f32, map, Tuple(f32).point(0.70711, 0.5, 0.70711), 0.375, 0.5);
    try testMapping(f32, map, Tuple(f32).point(0, -0.25, 1), 0.5, 0.75);
    try testMapping(f32, map, Tuple(f32).point(-0.70711, 0.5, 0.70711), 0.625, 0.5);
    try testMapping(f32, map, Tuple(f32).point(-1, 1.25, 0), 0.75, 0.25);
    try testMapping(f32, map, Tuple(f32).point(-0.70711, 0.5, -0.70711), 0.875, 0.5);
}

fn testAlignCheck(comptime T: type, u: T, v: T, expected: Color(T)) !void {
    const central = Pattern(T).solid(Color(T).new(1.0, 1.0, 1.0));
    const ul = Pattern(T).solid(Color(T).new(1.0, 0.0, 0.0));
    const ur = Pattern(T).solid(Color(T).new(1.0, 1.0, 0.0));
    const bl = Pattern(T).solid(Color(T).new(0.0, 1.0, 0.0));
    const br = Pattern(T).solid(Color(T).new(0.0, 1.0, 1.0));

    const pattern = UvPattern(T).uvAlignCheck(&central, &ul, &ur, &bl, &br);
    try testing.expect(pattern.uvPatternAt(u, v, undefined).approxEqual(expected));
}

test "Layout of the 'align check' pattern" {
    try testAlignCheck(f32, 0.5, 0.5, Color(f32).new(1.0, 1.0, 1.0));
    try testAlignCheck(f32, 0.1, 0.9, Color(f32).new(1.0, 0.0, 0.0));
    try testAlignCheck(f32, 0.9, 0.9, Color(f32).new(1.0, 1.0, 0.0));
    try testAlignCheck(f32, 0.1, 0.1, Color(f32).new(0.0, 1.0, 0.0));
    try testAlignCheck(f32, 0.9, 0.1, Color(f32).new(0.0, 1.0, 1.0));
}

test "Identifying the face of a cube from a point" {
    const Face = TextureMap(f32).Cubic.Face;
    const faceFromPoint = TextureMap(f32).Cubic.faceFromPoint;

    try testing.expectEqual(faceFromPoint(Tuple(f32).point(-1, 0.5, -0.25)), Face.left);
    try testing.expectEqual(faceFromPoint(Tuple(f32).point(1.1, -0.75, 0.8)), Face.right);
    try testing.expectEqual(faceFromPoint(Tuple(f32).point(0.1, 0.6, 0.9)), Face.front);
    try testing.expectEqual(faceFromPoint(Tuple(f32).point(-0.7, 0, -2)), Face.back);
    try testing.expectEqual(faceFromPoint(Tuple(f32).point(0.5, 1, 0.9)), Face.up);
    try testing.expectEqual(faceFromPoint(Tuple(f32).point(-0.2, -1.3, 1.1)), Face.down);
}

fn testUvMapping(comptime T: type, comptime faceFn: fn(Tuple(T)) [2]T, point: Tuple(T), u: T, v: T) !void {
    const tolerance = 1e-5;
    const uv = faceFn(point);
    try testing.expectApproxEqAbs(uv[0], u, tolerance);
    try testing.expectApproxEqAbs(uv[1], v, tolerance);
}

test "UV mapping the front face of a cube" {
    try testUvMapping(f32, TextureMap(f32).Cubic.uvFront, Tuple(f32).point(-0.5, 0.5, 1), 0.25, 0.75);
    try testUvMapping(f32, TextureMap(f32).Cubic.uvFront, Tuple(f32).point(0.5, -0.5, 1), 0.75, 0.25);
}

test "UV mapping the back face of a cube" {
    try testUvMapping(f32, TextureMap(f32).Cubic.uvBack, Tuple(f32).point(0.5, 0.5, -1), 0.25, 0.75);
    try testUvMapping(f32, TextureMap(f32).Cubic.uvBack, Tuple(f32).point(-0.5, -0.5, -1), 0.75, 0.25);
}

test "UV mapping the left face of a cube" {
    try testUvMapping(f32, TextureMap(f32).Cubic.uvLeft, Tuple(f32).point(-1, 0.5, -0.5), 0.25, 0.75);
    try testUvMapping(f32, TextureMap(f32).Cubic.uvLeft, Tuple(f32).point(-1, -0.5, 0.5), 0.75, 0.25);
}

test "UV mapping the right face of a cube" {
    try testUvMapping(f32, TextureMap(f32).Cubic.uvRight, Tuple(f32).point(1, 0.5, 0.5), 0.25, 0.75);
    try testUvMapping(f32, TextureMap(f32).Cubic.uvRight, Tuple(f32).point(1, -0.5, -0.5), 0.75, 0.25);
}

test "UV mapping the upper face of a cube" {
    try testUvMapping(f32, TextureMap(f32).Cubic.uvUp, Tuple(f32).point(-0.5, 1, -0.5), 0.25, 0.75);
    try testUvMapping(f32, TextureMap(f32).Cubic.uvUp, Tuple(f32).point(0.5, 1, 0.5), 0.75, 0.25);
}

test "UV mapping the lower face of a cube" {
    try testUvMapping(f32, TextureMap(f32).Cubic.uvDown, Tuple(f32).point(-0.5, -1, 0.5), 0.25, 0.75);
    try testUvMapping(f32, TextureMap(f32).Cubic.uvDown, Tuple(f32).point(0.5, -1, -0.5), 0.75, 0.25);
}

test "Finding the colors on a mapped cube" {
    const red    = Color(f32).new(1.0, 0.0, 0.0);
    const yellow = Color(f32).new(1.0, 1.0, 0.0);
    const brown  = Color(f32).new(1.0, 0.5, 0.0);
    const green  = Color(f32).new(0.0, 1.0, 0.0);
    const cyan   = Color(f32).new(0.0, 1.0, 1.0);
    const blue   = Color(f32).new(0.0, 0.0, 1.0);
    const purple = Color(f32).new(1.0, 0.0, 1.0);
    const white  = Color(f32).new(1.0, 1.0, 1.0);

    const solid_red    = Pattern(f32).solid(red);
    const solid_yellow = Pattern(f32).solid(yellow);
    const solid_brown  = Pattern(f32).solid(brown);
    const solid_green  = Pattern(f32).solid(green);
    const solid_cyan   = Pattern(f32).solid(cyan);
    const solid_blue   = Pattern(f32).solid(blue);
    const solid_purple = Pattern(f32).solid(purple);
    const solid_white  = Pattern(f32).solid(white);
    
    const left    = UvPattern(f32).uvAlignCheck(&solid_yellow, &solid_cyan, &solid_red, &solid_blue, &solid_brown);
    const front   = UvPattern(f32).uvAlignCheck(&solid_cyan, &solid_red, &solid_yellow, &solid_brown, &solid_green);
    const right   = UvPattern(f32).uvAlignCheck(&solid_red, &solid_yellow, &solid_purple, &solid_green, &solid_white);
    const back    = UvPattern(f32).uvAlignCheck(&solid_green, &solid_purple, &solid_cyan, &solid_white, &solid_blue);
    const up      = UvPattern(f32).uvAlignCheck(&solid_brown, &solid_cyan, &solid_purple, &solid_red, &solid_yellow);
    const down    = UvPattern(f32).uvAlignCheck(&solid_purple, &solid_brown, &solid_green, &solid_blue, &solid_white);
    const pattern = Pattern(f32).textureMap(TextureMap(f32).cubic(front, back, left, right, up, down));

    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-1, 0, 0)),       yellow);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-1, 0.9, -0.9)),  cyan);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-1, 0.9, 0.9)),   red);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-1, -0.9, -0.9)), blue);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-1, -0.9, 0.9)),  brown);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0, 0, 1)),        cyan);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-0.9, 0.9, 1)),   red);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.9, 0.9, 1)),    yellow);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-0.9, -0.9, 1)),  brown);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.9, -0.9, 1)),   green);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(1, 0, 0)),        red);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(1, 0.9, 0.9)),    yellow);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(1, 0.9, -0.9)),   purple);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(1, -0.9, 0.9)),   green);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(1, -0.9, -0.9)),  white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0, 0, -1)),       green);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.9, 0.9, -1)),   purple);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-0.9, 0.9, -1)),  cyan);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.9, -0.9, -1)),  white);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-0.9, -0.9, -1)), blue);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0, 1, 0)),        brown);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-0.9, 1, -0.9)),  cyan);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.9, 1, -0.9)),   purple);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-0.9, 1, 0.9)),   red);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.9, 1, 0.9)),    yellow);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0, -1, 0)),       purple);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-0.9, -1, 0.9)),  brown);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.9, -1, 0.9)),   green);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(-0.9, -1, -0.9)), blue);
    try testing.expectEqual(pattern.patternAt(Tuple(f32).point(0.9, -1, -0.9)),  white);
}

test "Canvas-based checker pattern in 2D" {
    const allocator = testing.allocator;

    const ppm = 
        \\P3
        \\10 10
        \\10
        \\0 0 0  1 1 1  2 2 2  3 3 3  4 4 4  5 5 5  6 6 6  7 7 7  8 8 8  9 9 9
        \\1 1 1  2 2 2  3 3 3  4 4 4  5 5 5  6 6 6  7 7 7  8 8 8  9 9 9  0 0 0
        \\2 2 2  3 3 3  4 4 4  5 5 5  6 6 6  7 7 7  8 8 8  9 9 9  0 0 0  1 1 1
        \\3 3 3  4 4 4  5 5 5  6 6 6  7 7 7  8 8 8  9 9 9  0 0 0  1 1 1  2 2 2
        \\4 4 4  5 5 5  6 6 6  7 7 7  8 8 8  9 9 9  0 0 0  1 1 1  2 2 2  3 3 3
        \\5 5 5  6 6 6  7 7 7  8 8 8  9 9 9  0 0 0  1 1 1  2 2 2  3 3 3  4 4 4
        \\6 6 6  7 7 7  8 8 8  9 9 9  0 0 0  1 1 1  2 2 2  3 3 3  4 4 4  5 5 5
        \\7 7 7  8 8 8  9 9 9  0 0 0  1 1 1  2 2 2  3 3 3  4 4 4  5 5 5  6 6 6
        \\8 8 8  9 9 9  0 0 0  1 1 1  2 2 2  3 3 3  4 4 4  5 5 5  6 6 6  7 7 7
        \\9 9 9  0 0 0  1 1 1  2 2 2  3 3 3  4 4 4  5 5 5  6 6 6  7 7 7  8 8 8
    ;

    const canvas = try Canvas(f32).fromPpm(allocator, ppm);
    defer canvas.destroy();

    const uv_pattern = UvPattern(f32).uvImage(canvas);

    try testing.expect(uv_pattern.uvPatternAt(0.0, 0.0, undefined).approxEqual(Color(f32).new(0.9, 0.9, 0.9)));
    try testing.expect(uv_pattern.uvPatternAt(0.3, 0.0, undefined).approxEqual(Color(f32).new(0.2, 0.2, 0.2)));
    try testing.expect(uv_pattern.uvPatternAt(0.6, 0.3, undefined).approxEqual(Color(f32).new(0.1, 0.1, 0.1)));
    try testing.expect(uv_pattern.uvPatternAt(1.0, 1.0, undefined).approxEqual(Color(f32).new(0.9, 0.9, 0.9)));
}
