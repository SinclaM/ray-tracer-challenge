const std = @import("std");
const testing = std.testing;
const pow = std.math.pow;

const Tuple = @import("tuple.zig").Tuple;
const Color = @import("color.zig").Color;
const Light = @import("light.zig").Light;
const Shape = @import("shapes/shape.zig").Shape;
const Pattern = @import("patterns/pattern.zig").Pattern;

/// A material for an object, backed by floats of type `T`.
/// Different materials behave differently under lighting,
/// and may have different patterns.
pub fn Material(comptime T: type) type {
    return struct {
        const Self = @This();

        color: Color(T) = Color(T).new(1.0, 1.0, 1.0),
        ambient: T = 0.1,
        diffuse: T = 0.9,
        specular: T = 0.9,
        shininess: T = 200.0,
        pattern: ?Pattern(T) = null,
        reflective: T = 0.0,
        transparency: T = 0.0,
        refractive_index: T = 1.0,

        /// Creates the default material.
        pub fn new() Self {
            return .{};
        }

        /// Determines what color should appear for the material `self`,
        /// when lit by `light`, on the shape `object`, at `point`, with
        /// the vector `point_to_eye` directed toward the camera, with
        /// `normal` as the surface normal, and whether the position is
        /// `in_shadow`.
        ///
        /// Assumes `point` is a point, `point_to_eye` is a vector, and
        /// `normal` is a vector.
        pub fn lighting(
            self: Self,
            light: Light(T),
            object: Shape(T),
            point: Tuple(T),
            point_to_eye: Tuple(T),
            normal: Tuple(T),
            in_shadow: bool,
        ) Color(T) {
            const color = if (self.pattern == null) self.color else self.pattern.?.patternAtShape(object, point);
            const effective_color = color.elementwiseMul(light.intensity);
            const point_to_light = light.position.sub(point).normalized();

            const ambient = effective_color.mul(self.ambient);
            var diffuse = Color(T).new(0.0, 0.0, 0.0);
            var specular = Color(T).new(0.0, 0.0, 0.0);

            if (in_shadow) {
                return ambient.add(diffuse).add(specular);
            }

            const light_dot_normal = point_to_light.dot(normal);
            if (light_dot_normal >= 0.0 ) {
                diffuse = effective_color.mul(self.diffuse * light_dot_normal);

                const reflected = point_to_light.reflect(normal);
                const reflect_dot_eye = reflected.negate().dot(point_to_eye);
                if (reflect_dot_eye > 0.0) {
                    specular = light.intensity.mul(self.specular * pow(T, reflect_dot_eye, self.shininess));
                }
            }

            return ambient.add(diffuse).add(specular);
        }
    };
}

test "Lighting" {
    const m = Material(f32).new();
    const position = Tuple(f32).point(0.0, 0.0, 0.0);

    {
        const placeholder_object = Shape(f32).sphere();
        const eyev = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 0.0, -10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, placeholder_object, position, eyev, normal, false);

        try testing.expect(result.approxEqual(Color(f32).new(1.9, 1.9, 1.9)));
    }

    {
        const placeholder_object = Shape(f32).sphere();
        const eyev = Tuple(f32).vec3(0.0, 1.0 / @sqrt(2.0), -1.0 / @sqrt(2.0));
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 0.0, -10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, placeholder_object, position, eyev, normal, false);

        try testing.expect(result.approxEqual(Color(f32).new(1.0, 1.0, 1.0)));
    }

    {
        const placeholder_object = Shape(f32).sphere();
        const eyev = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 10.0, -10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, placeholder_object, position, eyev, normal, false);

        try testing.expect(result.approxEqual(Color(f32).new(0.7364, 0.7364, 0.7364)));
    }

    {
        const placeholder_object = Shape(f32).sphere();
        const eyev = Tuple(f32).vec3(0.0, -1.0 / @sqrt(2.0), -1.0 / @sqrt(2.0));
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 10.0, -10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, placeholder_object, position, eyev, normal, false);

        try testing.expect(result.approxEqual(Color(f32).new(1.63639, 1.63639, 1.63639)));
    }

    {
        const placeholder_object = Shape(f32).sphere();
        const eyev = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 0.0, 10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, placeholder_object, position, eyev, normal, false);

        try testing.expect(result.approxEqual(Color(f32).new(0.1, 0.1, 0.1)));
    }

    {
        const placeholder_object = Shape(f32).sphere();
        const eyev = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 0.0, -10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, placeholder_object, position, eyev, normal, true);

        try testing.expect(result.approxEqual(Color(f32).new(0.1, 0.1, 0.1)));
    }
}

test "Lighting with pattern" {
    const white = Color(f32).new(1.0, 1.0, 1.0);
    const black = Color(f32).new(0.0, 0.0, 0.0);
    const solid_white = Pattern(f32).solid(white);
    const solid_black = Pattern(f32).solid(black);

    var m = Material(f32).new();
    m.pattern = Pattern(f32).stripes(&solid_white, &solid_black);
    m.ambient = 1.0;
    m.diffuse = 0.0;
    m.specular = 0.0;
    const eyev = Tuple(f32).vec3(0.0, 0.0, -1.0);
    const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
    const light = Light(f32).pointLight(Tuple(f32).point(0.0, 0.0, -10.0), Color(f32).new(1.0, 1.0, 1.0));
    const s = Shape(f32).sphere();

    const c1 = m.lighting(light, s, Tuple(f32).point(0.9, 0.0, 0.0), eyev, normal, false);
    const c2 = m.lighting(light, s, Tuple(f32).point(1.1, 0.0, 0.0), eyev, normal, false);
    try testing.expectEqual(c1, white);
    try testing.expectEqual(c2, black);
}
