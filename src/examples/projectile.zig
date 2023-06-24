const std = @import("std");
const print = std.debug.print;

const Canvas = @import("../raytracer/canvas.zig").Canvas;
const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Color = @import("../raytracer/color.zig").Color;

const Projectile = struct {
    position: Tuple(f32),
    velocity: Tuple(f32),
};

const Environment = struct {
    gravity: Tuple(f32),
    wind: Tuple(f32),

    pub fn tick(self: Environment, proj: *Projectile) void {
        proj.* = Projectile { .position = proj.position.add(proj.velocity),
                              .velocity = proj.velocity.add(self.gravity).add(self.wind) };
    }
};

pub fn simulate() !void {
    var proj = Projectile { .position = Tuple(f32).point(0.0, 1.0, 0.0),
                            .velocity = Tuple(f32).vec3(1.0, 1.8, 0.0).normalized().mul(11.25)};
    const env = Environment { .gravity = Tuple(f32).vec3(0.0, -0.1, 0.0),
                              .wind = Tuple(f32).vec3(-0.01, 0.0, 0.0)};


    comptime var width = 900;
    comptime var height = 550;

    const allocator = std.heap.page_allocator;

    var canvas = try Canvas(f32).new(allocator, width, height);
    defer canvas.destroy();

    while (proj.position.y > 0) {
        const x = @floatToInt(i32, proj.position.x);
        const y = @intCast(i32, canvas.height - 1) - @floatToInt(i32, proj.position.y);

        if (x > 0 and y > 0) {
            if (canvas.getPixelPointer(@intCast(usize, x), @intCast(usize, y))) |pixel| {
                pixel.* = Color(f32).new(1.0, 0.0, 0.0);
            }
        }

        env.tick(&proj);
    }

    const ppm = try canvas.ppm(allocator);
    defer allocator.free(ppm);

    const file = try std.fs.cwd().createFile(
        "images/projectile.ppm",
        .{ .read = true },
    );
    defer file.close();

    _ = try file.writeAll(ppm);
}

