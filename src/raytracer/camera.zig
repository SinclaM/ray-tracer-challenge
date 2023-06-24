const std = @import("std");
const testing = std.testing;
const pi = std.math.pi;
const Allocator = std.mem.Allocator;

const Tuple = @import("tuple.zig").Tuple;
const Matrix = @import("matrix.zig").Matrix;
const Ray = @import("ray.zig").Ray;
const World = @import("world.zig").World;
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("color.zig").Color;

pub fn Camera(comptime T: type) type {
    return struct {
        const Self = @This();

        hsize: usize,
        vsize: usize,
        fov: T,
        half_width: T,
        half_height: T,
        pixel_size: T,
        _transform: Matrix(T, 4) = Matrix(T, 4).identity(),
        _inverse_transform: Matrix(T, 4) = Matrix(T, 4).identity(),

        pub fn new(hsize: usize, vsize: usize, fov: T) Self {
            const half_view = @tan(fov / 2.0);
            const aspect = @intToFloat(T, hsize) / @intToFloat(T, vsize);
            var half_width = half_view * aspect; 
            var half_height = half_view;

            if (aspect >= 1.0) {
                half_width = half_view;
                half_height = half_view / aspect;
            }

            return .{
                .hsize = hsize,
                .vsize = vsize,
                .fov = fov,
                .half_width = half_width,
                .half_height = half_height,
                .pixel_size = (half_width * 2.0) / @intToFloat(T, hsize)
            };
        }

        pub fn setTransform(self: *Self, matrix: Matrix(T, 4)) !void {
            self._transform = matrix;
            self._inverse_transform = try matrix.inverse();
        }

        pub fn rayForPixel(self: Self, x: usize, y: usize) Ray(T) {
            const xoffset = (@intToFloat(T, x) + 0.5) * self.pixel_size;
            const yoffset = (@intToFloat(T, y) + 0.5) * self.pixel_size;

            const world_x = self.half_width - xoffset;
            const world_y = self.half_height - yoffset;

            const pixel = self._inverse_transform.tupleMul(Tuple(T).point(world_x, world_y, -1.0));
            const origin = self._inverse_transform.tupleMul(Tuple(T).point(0.0, 0.0, 0.0));
            const direction = pixel.sub(origin).normalized();

            return Ray(T).new(origin, direction);
        }

        pub fn render(self: Self, allocator: Allocator, world: World(T)) !Canvas(T) {
            var image = try Canvas(T).new(allocator, self.hsize, self.vsize);
            var x: usize = 0;
            while (x < self.hsize) : (x += 1) {
                var y: usize = 0;
                while (y < self.vsize) : (y += 1) {
                    const ray = self.rayForPixel(x, y);
                    const color = try world.colorAt(allocator, ray);
                    image.getPixelPointer(x, y).?.* = color;
                }
            }

            return image;
        }
    };
}

test "Camera creation" {
    const tolerance = 1e-5;

    {
        const c = Camera(f32).new(200, 125, pi / 2.0);
        try testing.expectApproxEqAbs(c.pixel_size, 0.01, tolerance);
        try testing.expectEqual(c._transform, Matrix(f32, 4).identity());
    }

    {
        const c = Camera(f32).new(125, 200, pi / 2.0);
        try testing.expectApproxEqAbs(c.pixel_size, 0.01, tolerance);
    }
}

test "rayForPixel" {
    {
        const c = Camera(f32).new(201, 101, pi / 2.0);
        const r = c.rayForPixel(100, 50);

        try testing.expect(r.origin.approxEqual(Tuple(f32).point(0.0, 0.0, 0.0)));
        try testing.expect(r.direction.approxEqual(Tuple(f32).vec3(0.0, 0.0, -1.0)));
    }

    {
        const c = Camera(f32).new(201, 101, pi / 2.0);
        const r = c.rayForPixel(0, 0);

        try testing.expect(r.origin.approxEqual(Tuple(f32).point(0.0, 0.0, 0.0)));
        try testing.expect(r.direction.approxEqual(Tuple(f32).vec3(0.66519, 0.33259, -0.66851)));
    }

    {
        var c = Camera(f32).new(201, 101, pi / 2.0);
        try c.setTransform(Matrix(f32, 4).identity().translate(0.0, -2.0, 5.0).rotateY(pi / 4.0));
        const r = c.rayForPixel(100, 50);

        try testing.expect(r.origin.approxEqual(Tuple(f32).point(0.0, 2.0, -5.0)));
        try testing.expect(r.direction.approxEqual(Tuple(f32).vec3(1.0 / @sqrt(2.0), 0.0, -1.0 / @sqrt(2.0))));
    }
}

test "Rendering" {
    const allocator = testing.allocator;

    const w = try World(f32).default(allocator);
    defer w.destroy();

    var c = Camera(f32).new(11.0, 11.0, pi / 2.0);
    const from = Tuple(f32).point(0.0, 0.0, -5.0);
    const to = Tuple(f32).point(0.0, 0.0, 0.0);
    const up = Tuple(f32).vec3(0.0, 1.0, 0.0);
    try c.setTransform(Matrix(f32, 4).viewTransform(from, to, up));

    var image = try c.render(allocator, w);
    defer image.destroy();

    try testing.expect(image.getPixelPointer(5, 5).?.*.approxEqual(Color(f32).new(0.38066, 0.47583, 0.2855)));
}
