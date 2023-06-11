const std = @import("std");

const tuple = @import("raytracer/tuple.zig");
const projectile = @import("examples/projectile.zig");

pub fn main() !void {
    projectile.simulate();
}
