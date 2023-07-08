const std = @import("std");

const projectile = @import("examples/projectile.zig");
const clock = @import("examples/clock.zig");
const silhouette = @import("examples/silhouette.zig");
const sphere = @import("examples/sphere.zig");
const simple_world = @import("examples/simple_world.zig");
const simple_superflat = @import("examples/simple_superflat.zig");
const fresnel = @import("examples/fresnel.zig");

const parseScene = @import("parser/parser.zig").parseScene;

pub fn main() !void {
    //try projectile.simulate();
    //try clock.drawHours();
    //try silhouette.drawSilhouette();
    //try sphere.drawSphere();
    //try simple_world.renderSimpleWorld();
    //try simple_superflat.renderSimpleSuperflat();
    //try fresnel.renderFresnel();

    const scenes_to_render = [_][]const u8 {
        "ch11_reflection_and_refraction",
        //"cover"
        //"ch12_cube"
    };

    inline for (scenes_to_render) |scene| {
        // Use an arena for the scene building, because I'm too lazy
        // to individually free the (relatively few) allocations that will
        // be made (e.g. for `Pattern`s) in `parseScene`.
        //
        // Don't use an arena for the main rendering allocator, though,
        // since there are many small allocs and frees made for intersections
        // during the render (TODO: they probably aren't even necessary).
        var arena = std.heap.ArenaAllocator.init(std.heap.raw_c_allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Parse the scene description.
        const scene_info = blk: {
            // Read in the json data for the scene. Could use `@embedFile` here.
            const scene_data = try std.fs.cwd().readFileAlloc(
                std.heap.raw_c_allocator, "scenes/" ++ scene ++ ".json", 65536
            );
            defer std.heap.raw_c_allocator.free(scene_data);
            break :blk try parseScene(f64, arena_allocator, scene_data);
        };

        const camera = &scene_info.camera;
        const world = &scene_info.world;

        // Do the ray tracing.
        const canvas = try camera.render(std.heap.raw_c_allocator, world.*);
        defer canvas.destroy();

        // Get the PPM data.
        const ppm = try canvas.ppm(std.heap.raw_c_allocator);
        defer std.heap.raw_c_allocator.free(ppm);

        // Save the image.
        const file = try std.fs.cwd().createFile(
            "images/" ++ scene ++ ".ppm",
            .{ .read = true },
        );
        defer file.close();

        _ = try file.writeAll(ppm);
    }
}
