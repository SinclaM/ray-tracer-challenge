const std = @import("std");

const Color = @import("color.zig").Color;
const Tuple = @import("tuple.zig").Tuple;

/// A light source, backed by floats of type `T`.
///
/// A light source has a `position` (it's location in world
/// cooridinates) and an `intensity` (it's strength and color).
pub fn Light(comptime T: type) type {
    return struct {
        const Self = @This();

        position: Tuple(T),
        intensity: Color(T),

        /// Creates a new point light at `position` with the given `intensity`.
        ///
        /// Assumes `position` is a point.
        pub fn pointLight(position: Tuple(T), intensity: Color(T)) Self {
            return .{ .position = position, .intensity = intensity };
        }
    };
}
