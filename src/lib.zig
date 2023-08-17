const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const Canvas = @import("raytracer/canvas.zig").Canvas;
const parseScene = @import("parsing/scene.zig").parseScene;
const SceneInfo = @import("parsing/scene.zig").SceneInfo;

const clamp = @import("raytracer/color.zig").clamp;
const Tuple = @import("raytracer/tuple.zig").Tuple;
const Matrix = @import("raytracer/matrix.zig").Matrix;

const Imports = struct {
    extern "env" fn _throwError(pointer: [*]const u8, length: u32) noreturn;
    pub fn throwError(message: []const u8) noreturn {
        _throwError(message.ptr, message.len);
    }
    extern fn jsConsoleLogWrite(ptr: [*]const u8, len: usize) void;
    extern fn jsConsoleLogFlush() void;
    extern fn loadObjData(name_ptr: [*]const u8, name_len: usize) [*:0]const u8;
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

        rendering_allocator: Allocator,
        scene_arena: ArenaAllocator,
        scene_info: SceneInfo(T),
        pixels: []u8,

        fn new(allocator: Allocator, scene: []const u8, dy: usize) !Self {
            var scene_arena = ArenaAllocator.init(allocator);
            errdefer scene_arena.deinit();

            // Parse the scene description.
            const scene_info = try parseScene(
                T, scene_arena.allocator(), allocator, scene, &Self.loadObjData
            );

            const pixels = try scene_arena.allocator().alloc(
                u8, 4 * scene_info.camera.hsize * dy
            );

            for (0..dy) |y| {
                for (0..scene_info.camera.hsize) |x| {
                    pixels[(y * scene_info.camera.hsize + x) * 4] = 0;
                    pixels[(y * scene_info.camera.hsize + x) * 4 + 1] = 0;
                    pixels[(y * scene_info.camera.hsize + x) * 4 + 2] = 0;
                    pixels[(y * scene_info.camera.hsize + x) * 4 + 3] = 0;
                }
            }

            return .{
                .rendering_allocator = allocator,
                .scene_arena = scene_arena,
                .scene_info = scene_info,
                .pixels = pixels,
            }; 
        }

        fn destroy(self: *Self) void {
            self.scene_arena.deinit();
            for (self.scene_info.world.objects.items) |*object| {
                switch (object.variant) {
                    .group => |*g| {
                        g.destroy();
                    },
                    else => {}
                }
            }
        }

        fn loadObjData(allocator: Allocator, file_name: []const u8) ![]const u8 {
            _ = allocator;

            const ptr = Imports.loadObjData(file_name.ptr, file_name.len);
            const obj = std.mem.span(ptr);
            return obj;
        }

        fn getCanvasInfo(self: Self) CanvasInfo {
            return .{
                .pixels = @ptrCast(self.pixels.ptr),
                .width = self.scene_info.camera.hsize,
                .height = self.scene_info.camera.vsize,
            };
        }

        fn render(self: *Self, y0: usize, dy: usize) !void {
            const camera = &self.scene_info.camera;
            const world = &self.scene_info.world;

            var arena = std.heap.ArenaAllocator.init(self.rendering_allocator);
            defer arena.deinit();

            for (y0..@min(y0 + dy, camera.vsize)) |y| {
                for (0..camera.hsize) |x| {
                    const ray = camera.rayForPixel(x, y);
                    const color = try world.colorAt(arena.allocator(), ray, 5);

                    self.pixels[((y - y0) * self.scene_info.camera.hsize + x) * 4] = clamp(T, color.r);
                    self.pixels[((y - y0) * self.scene_info.camera.hsize + x) * 4 + 1] = clamp(T, color.g);
                    self.pixels[((y - y0) * self.scene_info.camera.hsize + x) * 4 + 2] = clamp(T, color.b);
                    self.pixels[((y - y0) * self.scene_info.camera.hsize + x) * 4 + 3] = 255;

                    _ = arena.reset(.retain_capacity);
                }
            }
        }

        fn rotate_camera(self: *Self, angle: T) !void {
            var from = self.scene_info.camera._saved_from_to_up[0];
            const to = self.scene_info.camera._saved_from_to_up[1];
            const up = self.scene_info.camera._saved_from_to_up[2];

            const delta = Tuple(T).point(0.0, 0.0, 0.0).sub(to);
            from = from.add(delta);
            from = Matrix(T, 4).identity().rotate(up, angle).tupleMul(from);
            from = from.sub(delta);

            try self.scene_info.camera.setTransform(Matrix(T, 4).viewTransform(from, to, up));
            self.scene_info.camera._saved_from_to_up = [_]Tuple(T) { from, to, up };
        }

        fn move_camera(self: *Self, distance: T) !void {
            var from = self.scene_info.camera._saved_from_to_up[0];
            const to = self.scene_info.camera._saved_from_to_up[1];
            const up = self.scene_info.camera._saved_from_to_up[2];

            const delta = to.sub(from).mul(distance);
            from = from.add(delta);

            try self.scene_info.camera.setTransform(Matrix(T, 4).viewTransform(from, to, up));
            self.scene_info.camera._saved_from_to_up = [_]Tuple(T) { from, to, up };
        }
    };
}

// Calls to @panic are sent here.
// See https://ziglang.org/documentation/master/#panic
pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    Imports.throwError(message);
}

export fn wasmAlloc(length: usize) [*]const u8 {
    const slice = std.heap.wasm_allocator.alloc(u8, length) catch |err| @panic(@errorName(err));
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

export fn initRenderer(scene_ptr: [*:0]const u8, dy: usize) void {
    const allocator = std.heap.wasm_allocator;

    const scene = std.mem.span(scene_ptr);
    defer allocator.free(scene);

    if (Renderer(f64).new(allocator, scene, dy)) |r| {
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

export fn render(y0: usize, dy: usize) void {
    if (renderer) |*renderer_| {
        renderer_.render(y0, dy) catch |err| @panic(@errorName(err));
    } else {
        @panic("Renderer is uninitialized\n");
    }
}

export fn rotate_camera(angle: f64) void {
    if (renderer) |*renderer_| {
        renderer_.rotate_camera(angle) catch |err| @panic(@errorName(err));
    } else {
        @panic("Renderer is uninitialized\n");
    }
}

export fn move_camera(distance: f64) void {
    if (renderer) |*renderer_| {
        renderer_.move_camera(distance) catch |err| @panic(@errorName(err));
    } else {
        @panic("Renderer is uninitialized\n");
    }
}
