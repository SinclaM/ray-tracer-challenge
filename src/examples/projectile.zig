const print = @import("std").debug.print;

const Tuple = @import("../raytracer/tuple.zig").Tuple;

const Projectile = struct {
    position: Tuple(f32),
    velocity: Tuple(f32),
};

const Environment = struct {
    gravity: Tuple(f32),
    wind: Tuple(f32),

    pub fn tick(self: Environment, proj: *Projectile) void {
        proj.* = Projectile { .position = proj.position.add(proj.velocity),
                              .velocity = proj.velocity.add(self.gravity).add(self.wind) };
    }
};

pub fn simulate() void {
    var proj = Projectile { .position = Tuple(f32).new_point(0.0, 1.0, 0.0),
                            .velocity = Tuple(f32).new_vec3(1.0, 1.0, 1.0)};
    const env = Environment { .gravity = Tuple(f32).new_vec3(0.0, -0.1, 0.0),
                              .wind = Tuple(f32).new_vec3(-0.01, 0.0, 0.0)};

    while (proj.position.y > 0) {
        print("{}\n", .{ proj.position });
        env.tick(&proj);
    }
}

