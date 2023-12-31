const std = @import("std");
const zigimg = @import("zigimg");

const projectile = @import("examples/projectile.zig");
const clock = @import("examples/clock.zig");
const silhouette = @import("examples/silhouette.zig");
const sphere = @import("examples/sphere.zig");
const simple_world = @import("examples/simple_world.zig");
const simple_superflat = @import("examples/simple_superflat.zig");
const hexagon = @import("examples/hexagon.zig");

const parseScene = @import("parsing/scene.zig").parseScene;

fn loadFileData(allocator: std.mem.Allocator, file_name: []const u8) ![]const u8 {
    var data_dir = try std.fs.cwd().openDir("data", .{});
    defer data_dir.close();

    return try data_dir.readFileAlloc(
        allocator, file_name, std.math.pow(usize, 2, 32)
    );
}

pub fn main() !void {
    try projectile.simulate();
    try clock.drawHours();
    try silhouette.drawSilhouette();
    try sphere.drawSphere();
    try simple_world.renderSimpleWorld();
    try simple_superflat.renderSimpleSuperflat();
    try hexagon.renderHexagon();

    const scenes_to_render = [_][]const u8 {
        "cover",
        "cubes",
        "cylinders",
        "reflection_and_refraction",
        "fresnel",
        "groups",
        "teapot",
        "dragons",
        "nefertiti",
        "earth",
        "skybox",
        "xyz",
        "align_check"
    };

    // `raw_c_allocator` seems to play more nicely with Valgrind.
    const allocator = std.heap.raw_c_allocator;

    inline for (scenes_to_render) |scene| {
        // Use an arena for the scene building, because I'm too lazy
        // to individually free the (relatively few) allocations that will
        // be made (e.g. for `Pattern`s and `Group`s) in `parseScene`.
        //
        // Don't use an arena for the main rendering allocator, though,
        // since there are many small allocs and frees made for intersections
        // during the render (TODO: they probably aren't even necessary).
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Parse the scene description.
        const scene_info = blk: {
            // Read in the json data for the scene. Could use `@embedFile` here.
            const scene_data = try std.fs.cwd().readFileAlloc(
                allocator, "scenes/" ++ scene ++ ".json", 65536
            );
            defer allocator.free(scene_data);
            break :blk try parseScene(f64, arena_allocator, allocator, scene_data, &loadFileData);
        };

        const camera = &scene_info.camera;
        const world = &scene_info.world;

        defer {
            for (world.objects.items) |*object| {
                switch (object.variant) {
                    .group => |*g| {
                        g.destroy();
                    },
                    else => {}
                }
            }
        }

        // Do the ray tracing.
        const canvas = try camera.render(allocator, world.*);
        defer canvas.destroy();

        // Get the PPM data.
        var image = try canvas.to_image(allocator);
        defer image.deinit();

        try image.writeToFilePath("images" ++ std.fs.path.sep_str ++ scene ++ ".png", .{ .png = .{} });
    }
}
