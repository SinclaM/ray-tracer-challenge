const std = @import("std");
const pi = std.math.pi;

const Color = @import("../raytracer/color.zig").Color;
const Canvas = @import("../raytracer/canvas.zig").Canvas;
const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Matrix = @import("../raytracer/matrix.zig").Matrix;

pub fn drawHours() !void {
    const width = 100;
    const height = 100;

    const allocator = std.heap.c_allocator;

    var canvas = try Canvas(f32).new(allocator, width, height);
    defer canvas.destroy();

    const transform = Matrix(f32, 4).identity().rotateZ(pi / 6.0);
    var p = Tuple(f32).point(0.0, 45.0, 0.0);
    for (0..12) |_| {
        canvas.getPixelPointerMut(
            @intFromFloat(p.x + @as(f32, @floatFromInt(width / 2))),
            @intFromFloat(p.y + @as(f32, @floatFromInt(height / 2)))
        ).?.* = Color(f32).new(1.0, 1.0, 1.0);

        p = transform.tupleMul(p);
    }

    var image = try canvas.to_image(allocator);
    defer image.deinit();

    try image.writeToFilePath("images" ++ std.fs.path.sep_str ++ "clock.png", .{ .png = .{} });
}
