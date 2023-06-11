const print = @import("std").debug.print;

const Tuple = @import("../raytracer/tuple.zig").Tuple;

const Projectile = struct {
    position: Tuple,
    velocity: Tuple,
};

const Environment = struct {
    gravity: Tuple,
    wind: Tuple,

    pub fn tick(self: Environment, proj: *Projectile) void {
        proj.* = Projectile { .position = proj.position.add(proj.velocity),
                              .velocity = proj.velocity.add(self.gravity).add(self.wind) };
    }
};

pub fn simulate() void {
    var proj = Projectile { .position = Tuple.new_point(0.0, 1.0, 0.0),
                            .velocity = Tuple.new_vec3(1.0, 1.0, 1.0)};
    const env = Environment { .gravity = Tuple.new_vec3(0.0, -0.1, 0.0),
                              .wind = Tuple.new_vec3(-0.01, 0.0, 0.0)};

    while (proj.position.y > 0) {
        print("{}\n", .{ proj.position });
        env.tick(&proj);
    }
}

