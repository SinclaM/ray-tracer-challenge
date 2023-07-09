const std = @import("std");
const Allocator = std.mem.Allocator;

const Canvas = @import("raytracer/canvas.zig").Canvas;
const parseScene = @import("parser/parser.zig").parseScene;
const SceneInfo = @import("parser/parser.zig").SceneInfo;

const Imports = struct {
    extern fn jsConsoleLogWrite(ptr: [*]const u8, len: usize) void;
    extern fn jsConsoleLogFlush() void;
};

pub const Console = struct {
    pub const Logger = struct {
        pub const Error = error{};
        pub const Writer = std.io.Writer(void, Error, write);

        fn write(_: void, bytes: []const u8) Error!usize {
            Imports.jsConsoleLogWrite(bytes.ptr, bytes.len);
            return bytes.len;
        }
    };

    const logger = Logger.Writer{ .context = {} };
    pub fn log(comptime format: []const u8, args: anytype) void {
        logger.print(format, args) catch return;
        Imports.jsConsoleLogFlush();
    }
};

pub fn Renderer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        scene_info: SceneInfo(T),
        image: Canvas(T),
        current_y: usize = 0,

        fn new(allocator: Allocator, scene: []const u8) !Self {
            // Parse the scene description.
            const scene_info = try parseScene(T, allocator, scene);

            const image = try Canvas(T).new(allocator, scene_info.camera.hsize, scene_info.camera.vsize);

            return .{
                .allocator = allocator,
                .scene_info = scene_info,
                .image = image,
            }; 
        }

        fn destroy(self: *Self) void {
            // TODO: free scene_info
            self.image.destroy();
        }

        fn getCanvasInfo(self: Self) CanvasInfo(T) {
            return .{
                .pixels = @ptrCast(self.image.pixels.ptr),
                .width = self.image.width,
                .height = self.image.height,
            };
        }

        fn render(self: *Self, num_rows: usize) !bool {
            const camera = &self.scene_info.camera;
            const world = &self.scene_info.world;

            // TODO: An fba is every so slightly faster than an arena here, but is
            // more susceptible to OOM. I should probably just use the arena for
            // generality.
            var buffer = try self.allocator.alloc(u8, 1024 * 128);
            defer self.allocator.free(buffer);
            var fba = std.heap.FixedBufferAllocator.init(buffer);

            for (0..camera.hsize) |x| {
                for (self.current_y..@min(self.current_y + num_rows, camera.vsize)) |y| {
                    const ray = camera.rayForPixel(x, y);
                    const color = try world.colorAt(fba.allocator(), ray, 5);
                    self.image.getPixelPointer(x, y).?.* = color;
                    fba.reset();
                }
            }

            self.current_y += num_rows;

            const done = self.current_y >= camera.vsize;
            return done;
        }
    };
}

pub fn CanvasInfo(comptime T: type) type {
    return extern struct {
        pixels: [*]const T,
        width: usize,
        height: usize,
    };
}

export fn wasmAlloc(length: usize) [*]const u8 {
    const slice = std.heap.wasm_allocator.alloc(u8, length) catch
        @panic("failed to allocate memory");
    return slice.ptr;
}

var renderer: ?Renderer(f64) = null;

export fn initRenderer(scene_ptr: [*:0]const u8) [*]const f64 {
    const allocator = std.heap.wasm_allocator;

    const scene = std.mem.span(scene_ptr);
    defer allocator.free(scene);

    renderer = Renderer(f64).new(allocator, scene) catch @panic("Failed to initialize renderer\n");
    return renderer.?.getCanvasInfo().pixels;
}

export fn deinitRenderer() void {
    if (renderer) |*renderer_| {
        renderer_.destroy();
    }
}

export fn getWidth() usize {
    return renderer.?.getCanvasInfo().width;
}

export fn getHeight() usize {
    return renderer.?.getCanvasInfo().height;
}

export fn render(num_rows: usize) bool {
    if (renderer) |*renderer_| {
        return renderer_.render(num_rows) catch @panic("Failed to render\n");
    } else {
        @panic("Renderer is uninitialized\n");
    }
    
}
