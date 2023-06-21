const std = @import("std");
const print = std.debug.print;
const pi = std.math.pi;

const Color = @import("../raytracer/color.zig").Color;
const Canvas = @import("../raytracer/canvas.zig").Canvas;
const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Matrix = @import("../raytracer/matrix.zig").Matrix;

pub fn drawHours() !void {
    comptime var width = 100;
    comptime var height = 100;

    const allocator = std.heap.page_allocator;

    var canvas = try Canvas(f32).new(allocator, width, height);
    defer canvas.destroy();

    var i: usize = 0;
    var transform = Matrix(f32, 4).identity().rotate_z(pi / 6.0);
    var p = Tuple(f32).new_point(0.0, 45.0, 0.0);
    while (i < 12) : (i += 1) {
        canvas.get_pixel_pointer(
            @floatToInt(usize, p.x + @intToFloat(f32, width / 2)),
            @floatToInt(usize, p.y + @intToFloat(f32, height / 2))
        ).?.* = Color(f32).new(1.0, 1.0, 1.0);

        p = transform.tupleMul(p);
    }

    const ppm = try canvas.as_ppm(allocator);
    defer allocator.free(ppm);

    const file = try std.fs.cwd().createFile(
        "images/clock.ppm",
        .{ .read = true },
    );
    defer file.close();

    _ = try file.writeAll(ppm);
}
