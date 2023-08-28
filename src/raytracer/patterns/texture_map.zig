const std = @import("std");
const testing = std.testing;
const Tuple = @import("../tuple.zig").Tuple;
const Color = @import("../color.zig").Color;
const Pattern = @import("pattern.zig").Pattern;

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

pub fn UvPattern(comptime T: type) type {
    return struct {
        const Self = @This();

        variant: union(enum) {
            uv_checkers: UvCheckers(T),
        },

        pub fn uvCheckers(width: T, height: T, a: *const Pattern(T), b: *const Pattern(T)) Self {
            return .{
                .variant = .{ .uv_checkers = .{ .width = width, .height = height, .a = a, .b = b } }
            };
        }

        fn uvPatternAt(self: Self, u: T, v: T, object_point: Tuple(T)) Color(T) {
            const Tag = @typeInfo(@TypeOf(self.variant)).Union.tag_type.?;
            inline for (@typeInfo(Tag).Enum.fields) |field| {
                if (field.value == @intFromEnum(self.variant)) {
                    return @field(self.variant, field.name).uvPatternAt(u, v, object_point);
                }
            }
        }
    };
}

pub fn Mapping(comptime T: type) type {
    return struct {
        pub fn spherical(p: Tuple(T)) [2]T {
            const theta = std.math.atan2(T, p.x, p.z);

            const vec = Tuple(T).vec3(p.x, p.y, p.z);
            const radius = vec.magnitude();

            const phi = std.math.acos(p.y / radius);

            const raw_u = theta / (2.0 * std.math.pi);

            const u = 1 - (raw_u + 0.5);

            const v = 1 - phi / std.math.pi;

            return [_]T { u, v };
        }
    };
}

pub fn TextureMap(comptime T: type) type {
    return struct {
        const Self = @This();

        uv_pattern: UvPattern(T),
        uv_map: *const fn(Tuple(T)) [2]T,

        pub fn new(uv_pattern: UvPattern(T), uv_map: *const fn(Tuple(T)) [2]T) Self {
            return .{ .uv_pattern = uv_pattern, .uv_map = uv_map };
        }

        pub fn patternAt(self: Self, pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
            const uv = self.uv_map(pattern_point);
            return self.uv_pattern.uvPatternAt(uv[0], uv[1], object_point);
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

fn testSphericalMapping(comptime T: type, point: Tuple(T), u: T, v: T) !void {
    const tolerance = 1e-5;

    const uv = Mapping(T).spherical(point);
    try testing.expectApproxEqAbs(u, uv[0], tolerance);
    try testing.expectApproxEqAbs(v, uv[1], tolerance);
}

test "Using a spherical mapping on a 3D point" {
    try testSphericalMapping(f32, Tuple(f32).point(0, 0, -1), 0.0, 0.5);
    try testSphericalMapping(f32, Tuple(f32).point(1, 0, 0), 0.25, 0.5);
    try testSphericalMapping(f32, Tuple(f32).point(0, 0, 1), 0.5, 0.5);
    try testSphericalMapping(f32, Tuple(f32).point(-1, 0, 0), 0.75, 0.5);
    try testSphericalMapping(f32, Tuple(f32).point(0, 1, 0), 0.5, 1.0);
    try testSphericalMapping(f32, Tuple(f32).point(0, -1, 0), 0.5, 0.0);
    try testSphericalMapping(f32, Tuple(f32).point(1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0), 0), 0.25, 0.75);
}
