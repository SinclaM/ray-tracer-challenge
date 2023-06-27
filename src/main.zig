const projectile = @import("examples/projectile.zig");
const clock = @import("examples/clock.zig");
const silhouette = @import("examples/silhouette.zig");
const sphere = @import("examples/sphere.zig");
const simple_world = @import("examples/simple_world.zig");
const simple_superflat = @import("examples/simple_superflat.zig");

pub fn main() !void {
    //try projectile.simulate();
    //try clock.drawHours();
    //try silhouette.drawSilhouette();
    //try sphere.drawSphere();
    try simple_world.renderSimpleWorld();
    //try simple_superflat.renderSimpleSuperflat();
}
