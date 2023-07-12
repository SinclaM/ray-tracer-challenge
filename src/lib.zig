const std = @import("std");
const Allocator = std.mem.Allocator;

const Canvas = @import("raytracer/canvas.zig").Canvas;
const parseScene = @import("parser/parser.zig").parseScene;
const SceneInfo = @import("parser/parser.zig").SceneInfo;

const clamp = @import("raytracer/color.zig").clamp;

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
        pixels: []u8,
        current_y: usize = 0,

        fn new(allocator: Allocator, scene: []const u8) !Self {
            // Parse the scene description.
            const scene_info = try parseScene(T, allocator, scene);

            const pixels = try allocator.alloc(u8, 4 * scene_info.camera.hsize * scene_info.camera.vsize);
            // At this point nothing else can fail, but we might as well explicitly
            // include the `errdefer` if that changes in the future.
            errdefer allocator.free(pixels);

            for (0..scene_info.camera.hsize) |x| {
                for (0..scene_info.camera.vsize) |y| {
                    pixels[(y * scene_info.camera.hsize + x) * 4] = 0;
                    pixels[(y * scene_info.camera.hsize + x) * 4 + 1] = 0;
                    pixels[(y * scene_info.camera.hsize + x) * 4 + 2] = 0;
                    pixels[(y * scene_info.camera.hsize + x) * 4 + 3] = 0;
                }
            }

            return .{
                .allocator = allocator,
                .scene_info = scene_info,
                .pixels = pixels,
            }; 
        }

        fn destroy(self: *Self) void {
            self.allocator.free(self.pixels);
            self.scene_info.world.destroy();
        }

        fn getCanvasInfo(self: Self) CanvasInfo {
            return .{
                .pixels = @ptrCast(self.pixels.ptr),
                .width = self.scene_info.camera.hsize,
                .height = self.scene_info.camera.vsize,
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

                    self.pixels[(y * self.scene_info.camera.hsize + x) * 4] = clamp(T, color.r);
                    self.pixels[(y * self.scene_info.camera.hsize + x) * 4 + 1] = clamp(T, color.g);
                    self.pixels[(y * self.scene_info.camera.hsize + x) * 4 + 2] = clamp(T, color.b);
                    self.pixels[(y * self.scene_info.camera.hsize + x) * 4 + 3] = 255;

                    fba.reset();
                }
            }

            self.current_y += num_rows;

            const done = self.current_y >= camera.vsize;
            return done;
        }
    };
}

export fn wasmAlloc(length: usize) [*]const u8 {
    const slice = std.heap.wasm_allocator.alloc(u8, length) catch
        @panic("Failed to allocate memory!");
    return slice.ptr;
}

var renderer: ?Renderer(f64) = null;


// Returning a struct to WASM means the JS side will have to deconstruct
// the struct layout to extract the relevant information. That does not
// sound fun. So instead, we store our results in globals that we provide
// accessors for. It's not elegant at all, but it works fine.

fn Result(comptime T: type, comptime E: type) type {
    return union(enum) {
        ok: T,
        err: E,
    };
}

const CanvasInfo = extern struct {
    pixels: [*]const u8,
    width: usize,
    height: usize,
};

var initRendererResult: Result(CanvasInfo, [:0]const u8) = undefined;

export fn initRenderer(scene_ptr: [*:0]const u8) void {
    const allocator = std.heap.wasm_allocator;

    const scene = std.mem.span(scene_ptr);
    defer allocator.free(scene);

    if (Renderer(f64).new(allocator, scene)) |r| {
        renderer = r;
        initRendererResult = .{ .ok = renderer.?.getCanvasInfo() };
    } else |err| {
        initRendererResult = .{ .err = @errorName(err) };
    }
}

export fn initRendererIsOk() bool {
    switch (initRendererResult) {
        .ok => return true,
        .err => return false,
    }
}

export fn initRendererGetPixels() [*]const u8 {
    return initRendererResult.ok.pixels;
}

export fn initRendererGetWidth() usize {
    return initRendererResult.ok.width;
}

export fn initRendererGetHeight() usize {
    return initRendererResult.ok.height;
}

export fn initRendererGetErrPtr() [*]const u8 {
    return initRendererResult.err.ptr;
}

export fn initRendererGetErrLen() usize {
    return initRendererResult.err.len;
}

export fn deinitRenderer() void {
    if (renderer) |*renderer_| {
        renderer_.destroy();
    }
}

var renderResult: Result(bool, [:0]const u8) = undefined;

export fn renderIsOk() bool {
    switch (renderResult) {
        .ok => return true,
        .err => return false,
    }
}

export fn renderGetStatus() bool {
    return renderResult.ok;
}

export fn renderGetErrPtr() [*]const u8 {
    return renderResult.err.ptr;
}

export fn renderGetErrLen() usize {
    return renderResult.err.len;
}

export fn render(num_rows: usize) void {
    if (renderer) |*renderer_| {
        if (renderer_.render(num_rows)) |status| {
            renderResult = .{ .ok = status };
        } else |err| {
            renderResult = .{ .err = @errorName(err) };
        }
    } else {
        @panic("Renderer is uninitialized\n");
    }
}
