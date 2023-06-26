const std = @import("std");

const Color = @import("color.zig").Color;
const Tuple = @import("tuple.zig").Tuple;

pub fn Light(comptime T: type) type {
    return struct {
        const Self = @This();

        position: Tuple(T),
        intensity: Color(T),

        pub fn pointLight(position: Tuple(T), intensity: Color(T)) Self {
            return .{ .position = position, .intensity = intensity };
        }
    };
}
