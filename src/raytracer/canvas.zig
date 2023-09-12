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
        pub const ParseError = error { InvalidMagicNumber, InvalidDimensions, InvalidScale };

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

        pub fn from_ppm(allocator: Allocator, ppm_str: []const u8) !Self {
            var lines = std.mem.tokenizeScalar(u8, ppm_str, '\n');

            const first_line = lines.next();
            if (first_line == null or !std.mem.eql(u8, first_line.?, "P3")) {
                return Self.ParseError.InvalidMagicNumber;
            }

            var dimensions_line = lines.next() orelse { return Self.ParseError.InvalidDimensions; };
            while (std.mem.startsWith(u8, dimensions_line, "#")) {
                dimensions_line = lines.next() orelse { return Self.ParseError.InvalidDimensions; };
            }

            var dims = std.mem.tokenizeScalar(u8, dimensions_line, ' ');

            const width = try std.fmt.parseInt(
                usize, dims.next() orelse { return Self.ParseError.InvalidDimensions; }, 10
            );

            const height = try std.fmt.parseInt(
                usize, dims.next() orelse { return Self.ParseError.InvalidDimensions; }, 10
            );

            if (dims.next()) |_| {
                return Self.ParseError.InvalidDimensions;
            }

            var scale_line = lines.next() orelse { return Self.ParseError.InvalidScale; };
            while (std.mem.startsWith(u8, scale_line, "#")) {
                scale_line = lines.next() orelse { return Self.ParseError.InvalidScale; };
            }

            var scale_it = std.mem.tokenizeScalar(u8, scale_line, ' ');
            const scale = try std.fmt.parseInt(
                usize, scale_it.next() orelse { return Self.ParseError.InvalidScale; }, 10
            );

            if (scale_it.next()) |_| {
                return Self.ParseError.InvalidScale;
            }

            var pixels = try std.ArrayList(Color(T)).initCapacity(allocator, width * height);
            errdefer pixels.deinit();

            var current_pixel = Color(T).new(0.0, 0.0, 0.0);
            var current_channels_filled: u2 = 0;
            while (lines.next()) |line| {
                var tokens = std.mem.tokenizeScalar(u8, line, ' ');

                if (tokens.peek() != null and std.mem.startsWith(u8, tokens.peek().?, "#")) {
                    continue;
                }

                while (tokens.next()) |token| {
                    const val = try std.fmt.parseFloat(T, token) / @as(T, @floatFromInt(scale));
                    if (current_channels_filled == 0) {
                        current_pixel.r = val;
                    } else if (current_channels_filled == 1) {
                        current_pixel.g = val;
                    } else if (current_channels_filled == 2) {
                        current_pixel.b = val;
                        try pixels.append(current_pixel);
                    }

                    current_channels_filled = @mod(current_channels_filled + 1, 3);
                }
            }

            if (pixels.items.len != width * height) {
                return Self.ParseError.InvalidDimensions;
            }

            return .{ .width = width, .height = height, .pixels = try pixels.toOwnedSlice(), .allocator = allocator };
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

test "Reading a file with the wrong magic number" {
    const allocator = testing.allocator;
    const ppm = 
        \\P32
        \\1 1
        \\255
        \\0 0 0
    ;

    try testing.expectError(Canvas(f32).ParseError.InvalidMagicNumber, Canvas(f32).from_ppm(allocator, ppm));
}

test "Reading a PPM returns a canvas of the right size" {
    const allocator = testing.allocator;

    const ppm = 
        \\P3
        \\10 2
        \\255
        \\0 0 0  0 0 0  0 0 0  0 0 0  0 0 0
        \\0 0 0  0 0 0  0 0 0  0 0 0  0 0 0
        \\0 0 0  0 0 0  0 0 0  0 0 0  0 0 0
        \\0 0 0  0 0 0  0 0 0  0 0 0  0 0 0
    ;

    const canvas = try Canvas(f32).from_ppm(allocator, ppm);
    defer canvas.destroy();

    try testing.expectEqual(canvas.width, 10);
    try testing.expectEqual(canvas.height, 2);
}

test "Reading pixel data from a PPM file" {
    const allocator = testing.allocator;

    const ppm = 
        \\P3
        \\4 3
        \\255
        \\255 127 0  0 127 255  127 255 0  255 255 255
        \\0 0 0  255 0 0  0 255 0  0 0 255
        \\255 255 0  0 255 255  255 0 255  127 127 127
    ;

    var canvas = try Canvas(f32).from_ppm(allocator, ppm);
    defer canvas.destroy();

    try testing.expect(canvas.getPixelPointer(0, 0).?.*.approxEqual(Color(f32).new(1, 0.49804, 0)));
    try testing.expect(canvas.getPixelPointer(1, 0).?.*.approxEqual(Color(f32).new(0, 0.49804, 1)));
    try testing.expect(canvas.getPixelPointer(2, 0).?.*.approxEqual(Color(f32).new(0.49804, 1, 0)));
    try testing.expect(canvas.getPixelPointer(3, 0).?.*.approxEqual(Color(f32).new(1, 1, 1)));
    try testing.expect(canvas.getPixelPointer(0, 1).?.*.approxEqual(Color(f32).new(0, 0, 0)));
    try testing.expect(canvas.getPixelPointer(1, 1).?.*.approxEqual(Color(f32).new(1, 0, 0)));
    try testing.expect(canvas.getPixelPointer(2, 1).?.*.approxEqual(Color(f32).new(0, 1, 0)));
    try testing.expect(canvas.getPixelPointer(3, 1).?.*.approxEqual(Color(f32).new(0, 0, 1)));
    try testing.expect(canvas.getPixelPointer(0, 2).?.*.approxEqual(Color(f32).new(1, 1, 0)));
    try testing.expect(canvas.getPixelPointer(1, 2).?.*.approxEqual(Color(f32).new(0, 1, 1)));
    try testing.expect(canvas.getPixelPointer(2, 2).?.*.approxEqual(Color(f32).new(1, 0, 1)));
    try testing.expect(canvas.getPixelPointer(3, 2).?.*.approxEqual(Color(f32).new(0.49804, 0.49804, 0.49804)));
}

test "PPM parsing ignores comment lines" {
    const allocator = testing.allocator;

    const ppm = 
        \\P3
        \\# this is a comment
        \\2 1
        \\# this, too
        \\255
        \\# another comment
        \\255 255 255
        \\# oh, no, comments in the pixel data!
        \\255 0 255
    ;

    var canvas = try Canvas(f32).from_ppm(allocator, ppm);
    defer canvas.destroy();

    try testing.expect(canvas.getPixelPointer(0, 0).?.*.approxEqual(Color(f32).new(1, 1, 1)));
    try testing.expect(canvas.getPixelPointer(1, 0).?.*.approxEqual(Color(f32).new(1, 0, 1)));
}

test "PPM parsing allows an RGB triple to span lines" {
    const allocator = testing.allocator;

    const ppm = 
        \\P3
        \\1 1
        \\255
        \\51
        \\153

        \\204
    ;

    var canvas = try Canvas(f32).from_ppm(allocator, ppm);
    defer canvas.destroy();

    try testing.expect(canvas.getPixelPointer(0, 0).?.*.approxEqual(Color(f32).new(0.2, 0.6, 0.8)));
}

test "PPM parsing respects the scale setting" {
    const allocator = testing.allocator;

    const ppm = 
        \\P3
        \\2 2
        \\100
        \\100 100 100  50 50 50
        \\75 50 25  0 0 0
    ;

    var canvas = try Canvas(f32).from_ppm(allocator, ppm);
    defer canvas.destroy();

    try testing.expect(canvas.getPixelPointer(0, 1).?.*.approxEqual(Color(f32).new(0.75, 0.5, 0.25)));
}
