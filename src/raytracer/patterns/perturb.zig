const std = @import("std");
const testing = std.testing;
const pi = std.math.pi;

const Tuple = @import("../tuple.zig").Tuple;
const Matrix = @import("../matrix.zig").Matrix;
const Color = @import("../color.zig").Color;
const Pattern = @import("pattern.zig").Pattern;
const octaveNoise = @import("../noise.zig").octaveNoise;

/// A pattern that blends two other patterns,
/// backed by floats of type `T`.
pub fn Perturb(comptime T: type) type {
    return struct {
        const Self = @This();

        // a must live at least as long as the struct
        a: *const Pattern(T),
        info: PerturbInfo,

        pub const PerturbInfo = struct {
            scale_value: T = 0.3,
            octaves: usize = 3,
            persistence: T = 0.8,
        };

        pub fn new(a: *const Pattern(T), info: PerturbInfo) Self {
            return .{ .a = a, .info = info };
        }

        pub fn patternAt(self: Self, pattern_point: Tuple(T), object_point: Tuple(T)) Color(T) {
            _ = pattern_point;

            const offset = Tuple(T).vec3(
                octaveNoise(
                    T, object_point.x, object_point.y, object_point.z, self.info.octaves, self.info.persistence
                ),
                octaveNoise(
                    T, object_point.x, object_point.y, object_point.z + 1.0, self.info.octaves, self.info.persistence
                ),
                octaveNoise(
                    T, object_point.x, object_point.y, object_point.z + 2.0, self.info.octaves, self.info.persistence
                ),
            );

            return self.a.patternAt(object_point.add(offset.mul(self.info.scale_value)));
        }
    };
}
