const std = @import("std");
const testing = std.testing;

/// An rgb representation of a color, backed by floats of type `T`.
///
/// Channels scale from 0.0 (least intense) to 1.0 (most intense),
/// but they are not clamped to [0.0, 1.0] until being drawn to a canvas.
pub fn Color(comptime T: type) type {
    return packed struct {
        const Self = @This();
        const tolerance: T = 1e-5;

        r: T,
        g: T,
        b: T,

        /// Creates a new `Color`.
        pub inline fn new(r: T, g: T, b: T) Self {
            return .{ .r = r, .g = g, .b = b };
        }

        /// Tests whether two `Color`s should be considered equal.
        pub inline fn approxEqual(self: Self, other: Self) bool {
            return @fabs(self.r - other.r) < tolerance
                and @fabs(self.g - other.g) < tolerance
                and @fabs(self.b - other.b) < tolerance;
        }

        /// Adds two `Color`s elementwise.
        pub inline fn add(self: Self, other: Self) Self {
            return .{ .r = self.r + other.r,
                      .g = self.g + other.g,
                      .b = self.b + other.b };
        }

        /// Subtracts two `Color`s elementwise.
        pub inline fn sub(self: Self, other: Self) Self {
            return .{ .r = self.r - other.r,
                      .g = self.g - other.g,
                      .b = self.b - other.b };
        }

        /// Multiples a `Color` by `val`.
        pub inline fn mul(self: Self, val: T) Self {
            return .{ .r = self.r * val,
                      .g = self.g * val,
                      .b = self.b * val };
        }

        /// Multiples two `Color`s elementwise.
        pub inline fn elementwiseMul(self: Self, other: Self) Self {
            return .{ .r = self.r * other.r,
                      .g = self.g * other.g,
                      .b = self.b * other.b };
        }
    };
}

/// Clamps a channel to the [0, 255] range, converting
/// from float to u8.
pub fn clamp(comptime T: type, channel: T) u8 {
    var tmp: i128 = @intFromFloat(@round(channel * 255));

    if (tmp < 0) {
        tmp = 0;
    } else if (tmp > 255) {
        tmp = 255;
    }

    return @intCast(tmp);
}


test "Color ops" {
    // add
    var c1 = Color(f32).new(0.9, 0.6, 0.75);
    var c2 = Color(f32).new(0.7, 0.1, 0.25);
    try testing.expect(c1.add(c2).approxEqual(Color(f32).new(1.6, 0.7, 1.0)));

    // sub
    try testing.expect(c1.sub(c2).approxEqual(Color(f32).new(0.2, 0.5, 0.5)));

    // mul
    c1 = Color(f32).new(0.2, 0.3, 0.4);
    try testing.expect(c1.mul(2.0).approxEqual(Color(f32).new(0.4, 0.6, 0.8)));

    // elementwise mul
    c1 = Color(f32).new(1.0, 0.2, 0.4);
    c2 = Color(f32).new(0.9, 1.0, 0.1);
    try testing.expect(c1.elementwiseMul(c2).approxEqual(Color(f32).new(0.9, 0.2, 0.04)));

    // integer representation of channels
    try testing.expectEqual(clamp(f32, 0.1), 26);
    try testing.expectEqual(clamp(f32, 0.5), 128);
    try testing.expectEqual(clamp(f32, -0.1), 0);
    try testing.expectEqual(clamp(f32, 21.0), 255);
}
