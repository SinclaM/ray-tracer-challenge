const projectile = @import("examples/projectile.zig");
const clock = @import("examples/clock.zig");
const silhouette = @import("examples/silhouette.zig");

pub fn main() !void {
    try projectile.simulate();
    try clock.drawHours();
    try silhouette.drawSilhouette();
}
