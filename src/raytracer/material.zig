const std = @import("std");
const testing = std.testing;
const pow = std.math.pow;

const Tuple = @import("tuple.zig").Tuple;
const Color = @import("color.zig").Color;
const Light = @import("light.zig").Light;

pub fn Material(comptime T: type) type {
    return extern struct {
        const Self = @This();

        color: Color(T) = Color(T).new(1.0, 1.0, 1.0),
        ambient: T = 0.1,
        diffuse: T = 0.9,
        specular: T = 0.9,
        shininess: T = 200.0,

        pub fn new() Self {
            return .{};
        }

        pub fn lighting(
            self: Self, light: Light(T),
            point: Tuple(T),
            point_to_eye: Tuple(T),
            normal: Tuple(T),
            in_shadow: bool,
        ) Color(T) {
            const effective_color = self.color.elementwiseMul(light.intensity);
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
        const eyev = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 0.0, -10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, position, eyev, normal, false);

        try testing.expect(result.approxEqual(Color(f32).new(1.9, 1.9, 1.9)));
    }

    {
        const eyev = Tuple(f32).vec3(0.0, 1.0 / @sqrt(2.0), -1.0 / @sqrt(2.0));
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 0.0, -10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, position, eyev, normal, false);

        try testing.expect(result.approxEqual(Color(f32).new(1.0, 1.0, 1.0)));
    }

    {
        const eyev = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 10.0, -10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, position, eyev, normal, false);

        try testing.expect(result.approxEqual(Color(f32).new(0.7364, 0.7364, 0.7364)));
    }

    {
        const eyev = Tuple(f32).vec3(0.0, -1.0 / @sqrt(2.0), -1.0 / @sqrt(2.0));
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 10.0, -10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, position, eyev, normal, false);

        try testing.expect(result.approxEqual(Color(f32).new(1.63639, 1.63639, 1.63639)));
    }

    {
        const eyev = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 0.0, 10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, position, eyev, normal, false);

        try testing.expect(result.approxEqual(Color(f32).new(0.1, 0.1, 0.1)));
    }

    {
        const eyev = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const normal = Tuple(f32).vec3(0.0, 0.0, -1.0);
        const light = Light(f32).pointLight(Tuple(f32).point(0.0, 0.0, -10.0), Color(f32).new(1.0, 1.0, 1.0));
        const result = m.lighting(light, position, eyev, normal, true);

        try testing.expect(result.approxEqual(Color(f32).new(0.1, 0.1, 0.1)));
    }
}
