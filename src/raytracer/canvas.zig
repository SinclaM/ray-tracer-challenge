const std = @import("std");
const print = std.debug.print;
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Color = @import("color.zig").Color;
const clamp = @import("color.zig").clamp;

/// A container for pixels which can be written in different
/// image formats (currently only PPM).
pub fn Canvas(comptime T: type) type {
    return struct {
        const Self = @This();

        width: usize,
        height: usize,
        pixels: []Color(T),
        allocator: Allocator,

        /// Creates a new `Canvas` with dimensions `width` and `height`.
        /// Destroy with `destroy`.
        pub fn new(allocator: Allocator, width: usize, height: usize) !Self {
            var pixels = try allocator.alloc(Color(T), width * height);
            for (pixels) |*pixel| {
                pixel.* = Color(T).new(0.0, 0.0, 0.0);
            }

            return .{ .width = width, .height = height, .pixels = pixels, .allocator = allocator };
        }

        /// Frees the memory associated with the Canvas' pixels.
        pub fn destroy(self: Self) void {
            self.allocator.free(self.pixels);
        }

        /// Get's a pointer to the pixel at `x`, `y`. Returns `null` if
        /// `x`, `y` is out-of-bounds.
        ///
        /// Caller borrows the referent pixel mutably.
        pub fn getPixelPointer(self: *Self, x: usize, y: usize) ?*Color(T) {
            if (x >= self.width or y >= self.width) {
                return null;
            }
            return &self.pixels[y * self.width + x];
        }

        /// Dumps a `Canvas` in the PPM image format.
        ///
        /// Destroy with `allocator.free`.
        pub fn ppm(self: Self, allocator: Allocator) ![]u8 {
            var str = try std.ArrayList(u8).initCapacity(allocator, self.width * self.height * 12);
            var scratch: [32]u8 = undefined;

            // Header
            try str.appendSlice("P3\n");
            var slice = try std.fmt.bufPrint(&scratch, "{} {}\n", .{ self.width, self.height });
            try str.appendSlice(slice);
            try str.appendSlice("255\n");

            // Pixels
            var col: usize = 0;
            for (self.pixels, 0..) |pixel, i| {
                // ------ Red channel ------
                slice = (try std.fmt.bufPrint(&scratch, "{}", .{ clamp(T, pixel.r) }));

                if (col + slice.len >= 70) {
                    // If the red channel can't fit on the current line, break the
                    // line.
                    try str.append('\n');
                    col = 0;
                } else if (i % self.width != 0) {
                    // Otherwise, insert a space, but only if we aren't the first
                    // pixel in the line.
                    try str.append(' ');
                    col += 1;
                }
                // Actually write the channel value.
                try str.appendSlice(slice);
                col += slice.len;

                // ----- Green channel -----
                slice = (try std.fmt.bufPrint(&scratch, "{}", .{ clamp(T, pixel.g) }));

                if (col + slice.len >= 70) {
                    // If the green channel can't fit on the current line, break the
                    // line.
                    try str.append('\n');
                    col = 0;
                } else {
                    // Otherwise, insert a space.
                    try str.append(' ');
                    col += 1;
                }
                // Actually write the channel value.
                try str.appendSlice(slice);
                col += slice.len;

                // ----- Blue channel -----
                slice = (try std.fmt.bufPrint(&scratch, "{}", .{ clamp(T, pixel.b) }));

                if (col + slice.len >= 70) {
                    // If the blue channel can't fit on the current line, break the
                    // line.
                    try str.append('\n');
                    col = 0;
                } else {
                    // Otherwise, insert a space.
                    try str.append(' ');
                    col += 1;
                }
                // Actually write the channel value.
                try str.appendSlice(slice);
                col += slice.len;

                if ((i + 1) % self.width == 0) {
                    // Break the line if this is the last pixel in the row.
                    try str.append('\n');
                    col = 0;
                }
            }

            return str.toOwnedSlice();
        }
    };
}

test "Canvas" {
    var c = try Canvas(f32).new(testing.allocator, 5, 3);
    defer c.destroy();

    c.getPixelPointer(0, 0).?.*.r = 1.5;
    c.getPixelPointer(2, 1).?.*.g = 0.5;
    c.getPixelPointer(4, 2).?.* = Color(f32).new(-0.5, 0.0, 1.0);

    const ppm = try c.ppm(testing.allocator);
    defer testing.allocator.free(ppm);

    const expected_ppm =
        \\P3
        \\5 3
        \\255
        \\255 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        \\0 0 0 0 0 0 0 128 0 0 0 0 0 0 0
        \\0 0 0 0 0 0 0 0 0 0 0 0 0 0 255
        \\
    ;

    try testing.expectEqualStrings(expected_ppm, ppm);

    var c2 = try Canvas(f32).new(testing.allocator, 10, 2);
    defer c2.destroy();

    for (c2.pixels) |*pixel| {
        pixel.* = Color(f32).new(1, 0.8, 0.6);
    }

    const ppm2 = try c2.ppm(testing.allocator);
    defer testing.allocator.free(ppm2);

    const expected_ppm2 = 
        \\P3
        \\10 2
        \\255
        \\255 204 153 255 204 153 255 204 153 255 204 153 255 204 153 255 204
        \\153 255 204 153 255 204 153 255 204 153 255 204 153
        \\255 204 153 255 204 153 255 204 153 255 204 153 255 204 153 255 204
        \\153 255 204 153 255 204 153 255 204 153 255 204 153
        \\
    ;

    try testing.expectEqualStrings(expected_ppm2, ppm2);
}
