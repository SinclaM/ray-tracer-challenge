// Based on Java reference implementation of improved noise - copyright 2002 Ken Perlin.
// https://mrl.cs.nyu.edu/~perlin/noise/

const testing = @import("std").testing;

const permutation = [_]u8 {
    151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 
    140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 
    247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 
    57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 
    74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 
    60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 
    65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 
    200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 
    52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 
    207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 
    119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 
    129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 
    218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 
    81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 
    184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 
    222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180
};

const p = blk: {
    comptime var i = 0;
    comptime var self: [512]u8 = undefined;
    while (i < 256) : (i += 1) {
        self[256 + i] = permutation[i];
        self[i] = permutation[i];
    }
    break :blk self;
};

pub fn octaveNoise(comptime T: type, x: T, y: T, z: T, octaves: usize, persistence: T) T {
    var total: T = 0.0;
    var frequency: T = 1.0;
    var amplitude: T = 1.0;
    var max_value: T = 0.0; // Used for normalizing result to 0.0 - 1.0
    var i: usize = 0;
    while (i < octaves) : (i += 1) {
        total += noise(T, x * frequency, y * frequency, z * frequency) * amplitude;

        max_value += amplitude;

        amplitude *= persistence;
        frequency *= 2.0;
      }

  return total / max_value;
}

pub fn noise(comptime T: type, x_: T, y_: T, z_: T) T {
    @setRuntimeSafety(false);

    var x = x_;
    var y = y_;
    var z = z_;

    // Find unit cube that contains point
    const X = @floatToInt(u8, @floor(x)) & 255;
    const Y = @floatToInt(u8, @floor(y)) & 255;
    const Z = @floatToInt(u8, @floor(z)) & 255;
    x -= @floor(x);                          
    y -= @floor(y);                          
    z -= @floor(z);

    // For each of x, y, z
    const u = fade(T, x);
    const v = fade(T, y);
    const w = fade(T, z);

    // Hash coordinates of the 8 cube corners
    const A  = p[X]     + Y;
    const AA = p[A]     + Z;
    const AB = p[A + 1] + Z;
    const B  = p[X + 1] + Y;
    const BA = p[B]     + Z;
    const BB = p[B + 1] + Z;

    // And add blended results from 8 corners of cube
    return lerp(T, w, lerp(T, v, lerp(T, u, grad(T, p[AA  ], x  , y  , z   ),
                                            grad(T, p[BA  ], x-1, y  , z   )),
                                 lerp(T, u, grad(T, p[AB  ], x  , y-1, z   ),
                                            grad(T, p[BB  ], x-1, y-1, z   ))),
                      lerp(T, v, lerp(T, u, grad(T, p[AA+1], x  , y  , z-1 ),
                                            grad(T, p[BA+1], x-1, y  , z-1 )),
                                 lerp(T, u, grad(T, p[AB+1], x  , y-1, z-1 ),
                                            grad(T, p[BB+1], x-1, y-1, z-1 ))));
}
fn fade(comptime T: type, t: T) T {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

fn lerp(comptime T: type, t: T, a: T, b: T) T {
    return a + t * (b - a);
}

fn grad(comptime T: type, hash: u8, x: T, y: T, z: T) T {
    // Convert low 4 bits of hash code into 12 gradient direction.
    const h = hash & 15;
    const u = if (h < 8) x else y;
    const v = if (h < 4) y else (if (h == 12 or h==14) x else z);
    return (if (h & 1 == 0) u else -u) + (if (h & 2 == 0) v else -v);
}

test "noise" {
    try testing.expect(noise(f64,  3.14, 42, 7) == 0.13691995878400012);
    try testing.expect(noise(f64, -4.20, 10, 6) == 0.14208000000000043);
}
