const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const Canvas = @import("raytracer/canvas.zig").Canvas;
const parseScene = @import("parsing/scene.zig").parseScene;
const SceneInfo = @import("parsing/scene.zig").SceneInfo;

const clamp = @import("raytracer/color.zig").clamp;
const Tuple = @import("raytracer/tuple.zig").Tuple;
const Matrix = @import("raytracer/matrix.zig").Matrix;

const Libc = struct {
    const EOF = -1; // in musl (and glibc)
    extern fn fopen(pathname: [*:0]const c_char, mode: [*:0]const c_char) ?*anyopaque;
    extern fn fclose(stream: *anyopaque) c_int;
    extern fn feof(stream: *anyopaque) c_int;
    extern fn fgetc(stream: *anyopaque) c_int;
};

fn readFile(allocator: Allocator, pathname: []const u8) ![]u8 {
    var pathnameZ = try allocator.alloc(u8, pathname.len + 1);
    defer allocator.free(pathnameZ);

    std.mem.copyForwards(u8, pathnameZ, pathname);
    pathnameZ[pathname.len] = 0;

    const maybe_f = Libc.fopen(@ptrCast(pathnameZ.ptr), @ptrCast("rb"));
    const f = maybe_f orelse { return error.CannotOpenFile; };
    defer { _ = Libc.fclose(f); }

    var string = std.ArrayList(u8).init(allocator);

    // TODO: this is so slow, switch to fread.
    while (Libc.feof(f) == 0) {
        const c = Libc.fgetc(f);
        if (c != Libc.EOF) {
            try string.append(@intCast(c));
        }
    }

    return try string.toOwnedSlice();
}

pub fn Renderer(comptime T: type) type {
    return struct {
        const Self = @This();

        rendering_allocator: Allocator,
        scene_arena: ArenaAllocator,
        scene_info: SceneInfo(T),
        pixels: []u8,
        n_threads: usize,
        render_thread_pool: std.Thread.Pool = undefined,
        finished_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

        fn new(allocator: Allocator, scene: []const u8, n_threads: usize) !Self {
            var scene_arena = ArenaAllocator.init(allocator);
            errdefer scene_arena.deinit();

            // Parse the scene description.
            const scene_info = try parseScene(
                T, scene_arena.allocator(), allocator, scene, &Self.loadFileData
            );

            const pixels = try scene_arena.allocator().alloc(
                u8, 4 * scene_info.camera.hsize * scene_info.camera.vsize
            );

            for (0..scene_info.camera.vsize) |y| {
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
                .n_threads = n_threads,
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

        fn loadFileData(allocator: Allocator, file_name: []const u8) ![]const u8 {
            return try readFile(allocator, file_name);
        }

        fn getCanvasInfo(self: Self) CanvasInfo {
            return .{
                .pixels = @ptrCast(self.pixels.ptr),
                .width = self.scene_info.camera.hsize,
                .height = self.scene_info.camera.vsize,
            };
        }

        fn renderWorker(self: *Self, y: usize) void {
            const camera = &self.scene_info.camera;
            const world = &self.scene_info.world;

            var arena = std.heap.ArenaAllocator.init(self.rendering_allocator);
            defer arena.deinit();

            for (0..camera.hsize) |x| {
                const ray = camera.rayForPixel(x, y);
                const color = world.colorAt(arena.allocator(), ray, 5) catch |err| @panic(@errorName(err));

                self.pixels[(y * self.scene_info.camera.hsize + x) * 4] = clamp(T, color.r);
                self.pixels[(y * self.scene_info.camera.hsize + x) * 4 + 1] = clamp(T, color.g);
                self.pixels[(y * self.scene_info.camera.hsize + x) * 4 + 2] = clamp(T, color.b);
                self.pixels[(y * self.scene_info.camera.hsize + x) * 4 + 3] = 255;

                _ = arena.reset(.retain_capacity);
            }

            _  = self.finished_count.fetchAdd(1, .Monotonic);
        }

        fn startRender(self: *Self) !void {
            self.finished_count.store(0, .Monotonic);

            try self.render_thread_pool.init(.{ .allocator = self.rendering_allocator, .n_jobs = self.n_threads });
            for (0..self.scene_info.camera.vsize) |y| {
                try self.render_thread_pool.spawn(Self.renderWorker, .{ self, y });
            }
        }

        fn rotateCamera(self: *Self, angle: T) !void {
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

        fn moveCamera(self: *Self, distance: T) !void {
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

var init_renderer_result: Result(CanvasInfo, [:0]const u8) = undefined;
var init_renderer_thread: std.Thread = undefined;
var init_renderer_thread_done = false;

fn initRendererWorker(scene_ptr: [*:0]const u8, n_threads: usize) void {
    const allocator = std.heap.raw_c_allocator;

    const scene = std.mem.span(scene_ptr);

    if (Renderer(f64).new(allocator, scene, n_threads)) |r| {
        renderer = r;
        init_renderer_result = .{ .ok = renderer.?.getCanvasInfo() };
    } else |err| {
        init_renderer_result = .{ .err = @errorName(err) };
    }

    init_renderer_thread_done = true;
}

export fn startInitRenderer(scene_ptr: [*:0]const u8, n_threads: usize) void {
    init_renderer_thread_done = false;
    init_renderer_thread = std.Thread.spawn(.{}, initRendererWorker, .{scene_ptr, n_threads})
        catch |err| @panic(@errorName(err));
}

export fn tryFinishInitRenderer() bool {
    if (init_renderer_thread_done) {
        init_renderer_thread.join();
    }
    return init_renderer_thread_done;
}

export fn initRendererIsOk() bool {
    switch (init_renderer_result) {
        .ok => return true,
        .err => return false,
    }
}

export fn initRendererGetPixels() [*]const u8 {
    return init_renderer_result.ok.pixels;
}

export fn initRendererGetWidth() usize {
    return init_renderer_result.ok.width;
}

export fn initRendererGetHeight() usize {
    return init_renderer_result.ok.height;
}

export fn initRendererGetErr() [*]const u8 {
    return init_renderer_result.err.ptr;
}

export fn deinitRenderer() void {
    if (renderer) |*renderer_| {
        renderer_.destroy();
    }
}

export fn startRender() void {
    if (renderer) |*renderer_| {
        renderer_.startRender() catch |err| @panic(@errorName(err));
    } else {
        @panic("Renderer is uninitialized\n");
    }
}

export fn tryFinishRender() bool {
    if (renderer) |*renderer_| {
        const finished = renderer_.finished_count.load(.Monotonic) == renderer_.scene_info.camera.vsize;
        if (finished) {
            renderer_.render_thread_pool.deinit();
        }
        return finished;
    } else {
        @panic("Renderer is uninitialized\n");
    }
}

export fn rotateCamera(angle: f64) void {
    if (renderer) |*renderer_| {
        renderer_.rotateCamera(angle) catch |err| @panic(@errorName(err));
    } else {
        @panic("Renderer is uninitialized\n");
    }
}

export fn moveCamera(distance: f64) void {
    if (renderer) |*renderer_| {
        renderer_.moveCamera(distance) catch |err| @panic(@errorName(err));
    } else {
        @panic("Renderer is uninitialized\n");
    }
}
