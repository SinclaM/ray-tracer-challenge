const projectile = @import("examples/projectile.zig");
const clock = @import("examples/clock.zig");

pub fn main() !void {
    try projectile.simulate();
    try clock.drawHours();
}
