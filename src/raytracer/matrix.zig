const std = @import("std");
const testing = std.testing;
const pi = std.math.pi;

const Tuple = @import("tuple.zig").Tuple;

pub const MatrixError = error { NotInvertible };

/// A square matrix of size `N`, backed by floats of type `T`.
pub fn Matrix(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();
        const tolerance: T = 1e-5;

        data: [N][N]T,

        /// Creates a `Matrix` from an `N` x `N` buffer.
        pub fn new(data: [N][N]T) Self {
            return .{ .data = data };
        }

        /// Creates an uninitialized `Matrix`.
        pub fn newUninit() Self {
            const data: [N][N]T = undefined;
            return .{ .data = data };
        }

        /// Creates the zero matrix of size `N`.
        pub fn zero() Self {
            var data: [N][N]T = undefined;
            for (data) |*row| {
                for (row) |*val| {
                    val.* = 0.0;
                }
            }
            return .{ .data = data };
        }

        /// Creates the `N` x `N` identity matrix.
        pub fn identity() Self {
            var matrix = Self.zero();

            var i: usize = 0;
            while (i < N) {
                matrix.data[i][i] = 1.0;
                i += 1;
            }

            return matrix;
        }

        /// Computes the transformation needed move a world as if the camera
        /// is positioned at `from`, facing `to`, with `up` as the upwards direction.
        ///
        /// Assumes `from` is a point, `to` is a point, and `up` is a vector.
        pub fn viewTransform(from: Tuple(T), to: Tuple(T), up: Tuple(T)) Self {
            const forward = to.sub(from).normalized();
            const left = forward.cross(up.normalized());
            const true_up = left.cross(forward);

            const orientation = Matrix(T, 4).new([4][4]T{
                [_]T{ left.x    , left.y    ,  left.z    , 0.0 },
                [_]T{ true_up.x , true_up.y ,  true_up.z , 0.0 },
                [_]T{ -forward.x, -forward.y,  -forward.z, 0.0 },
                [_]T{    0.0    ,    0.0    ,     0.0    , 1.0 },
            });

            return orientation.mul(Matrix(T, 4).identity().translate(-from.x, -from.y, -from.z));
        }

        /// Tests whether two matrices should be considered equal.
        pub fn approxEqual(self: Self, other: Self) bool {
            var row: usize = 0;
            while (row < N) {
                var col: usize = 0;
                while (col < N) {
                    if (@fabs(self.data[row][col] - other.data[row][col]) > tolerance) {
                        return false;
                    }
                    col += 1;
                }
                row += 1;
            }
            return true;
        }

        /// Multiplies the matrices `self` and `other` (not elementwise).
        pub fn mul(self: Self, other: Self) Self {
            var result = Self.newUninit();
            var row: usize = 0;
            while (row < N) : (row += 1) {
                var col: usize = 0;
                while (col < N) : (col += 1) {
                    var i: usize = 0;
                    var sum: T = 0;
                    while (i < N) : (i += 1) {
                        sum += self.data[row][i] * other.data[i][col];
                    }
                    result.data[row][col] = sum;
                }
            }

            return result;
        }

        /// Multiplies `self` with `tup`.
        ///
        /// Assumes `tup` is a vector.
        pub fn tupleMul(self: Self, tup: Tuple(T)) Tuple(T) {
            var result = Tuple(T).new(0.0, 0.0, 0.0, 0.0);

            var row = Tuple(T).fromBuf(self.data[0]);
            result.x = row.dot(tup);

            row = Tuple(T).fromBuf(self.data[1]);
            result.y = row.dot(tup);

            row = Tuple(T).fromBuf(self.data[2]);
            result.z = row.dot(tup);

            row = Tuple(T).fromBuf(self.data[3]);
            result.w = row.dot(tup);

            return result;
        }

        /// Transposes `self`.
        pub fn transpose(self: Self) Self {
            var transposed = Self.newUninit();

            var row: usize = 0;
            while (row < N) {
                var col: usize = 0;
                while (col < N) {
                    transposed.data[row][col] = self.data[col][row];
                    col += 1;
                }
                row += 1;
            }

            return transposed;
        }

        /// Finds the submatrix of `self` excluding `row` and `col`.
        pub fn submatrix(self: Self, row: usize, col: usize) Matrix(T, N - 1) {
            var sub = Matrix(T, N - 1).newUninit();

            var r: usize = 0;
            while (r < N) : (r += 1) {
                if (r == row) { continue; }

                var c: usize = 0;
                while (c < N) : (c += 1) {
                    if (c == col) { continue; }

                    sub.data[r - @boolToInt(r > row)][c - @boolToInt(c > col)] = self.data[r][c];
                }
            }

            return sub;
        }

        /// Computes the minor of `self` at `row`, `col`.
        pub fn minor(self: Self, row: usize, col: usize) T {
            return self.submatrix(row, col).det();
        }

        /// Computes the cofactor of `self` at `row`, `col`.
        pub fn cofactor(self: Self, row: usize, col: usize) T {
            if ((row + col) % 2 == 0) {
                return self.minor(row, col);
            } else {
                return -self.minor(row, col);
            }
        }

        /// Computes the determinant.
        pub fn det(self: Self) T {
            var det_: T = 0.0;

            if (N == 2) {
                det_ = self.data[0][0] * self.data[1][1] - self.data[0][1] * self.data[1][0];
            } else {
                var col: usize = 0;
                while (col < N) : (col += 1) {
                    det_ += self.data[0][col] * self.cofactor(0, col);
                }
            }

            return det_;
        }

        /// Finds the inverse of `self`. Fails if `self` is not invertible.
        pub fn inverse(self: Self) !Self {
            const det_ = self.det();
            if (@fabs(det_) < Self.tolerance) {
                return MatrixError.NotInvertible;
            }

            var inverse_ = Self.newUninit();

            var row: usize = 0;
            while (row < N) : (row += 1) {
                var col: usize = 0;
                while (col < N) : (col += 1) {
                    inverse_.data[col][row] = self.cofactor(row, col) / det_;
                }
            }

            return inverse_;
        }

        /// Produces a transformation that will translate vectors by
        /// `x`, `y`, and `z` in each respective direction after the
        /// transformation applied by `self`.
        pub fn translate(self: Self, x: T, y: T, z: T) Self {
            const translation = Matrix(T, 4).new([4][4]T{
                [_]T{ 1.0, 0.0, 0.0, x },
                [_]T{ 0.0, 1.0, 0.0, y },
                [_]T{ 0.0, 0.0, 1.0, z },
                [_]T{ 0.0, 0.0, 0.0, 1.0 },
            });

            return translation.mul(self);
        }

        /// Produces a transformation that will scale vectors by
        /// `x`, `y`, and `z` in each respective direction after the
        /// transformation applied by `self`.
        pub fn scale(self: Self, x: T, y: T, z: T) Self {
            const scaling = Matrix(T, 4).new([4][4]T{
                [_]T{  x , 0.0, 0.0, 0.0 },
                [_]T{ 0.0,  y , 0.0, 0.0 },
                [_]T{ 0.0, 0.0,  z , 0.0 },
                [_]T{ 0.0, 0.0, 0.0, 1.0 },
            });

            return scaling.mul(self);
        }

        /// Produces a transformation that will rotate vectors by `angle`
        /// about the x-axis after the transformation applied by `self`.
        pub fn rotateX(self: Self, angle: T) Self {
            const rotation = Matrix(T, 4).new([4][4]T{
                [_]T{ 1.0,    0.0     ,     0.0     , 0.0 },
                [_]T{ 0.0, @cos(angle), -@sin(angle), 0.0 },
                [_]T{ 0.0, @sin(angle),  @cos(angle), 0.0 },
                [_]T{ 0.0,    0.0     ,     0.0     , 1.0 },
            });

            return rotation.mul(self);
        }

        /// Produces a transformation that will rotate vectors by `angle`
        /// about the y-axis after the transformation applied by `self`.
        pub fn rotateY(self: Self, angle: T) Self {
            const rotation = Matrix(T, 4).new([4][4]T{
                [_]T{ @cos(angle) , 0.0, @sin(angle), 0.0 },
                [_]T{    0.0      , 1.0,    0.0     , 0.0 },
                [_]T{ -@sin(angle), 0.0, @cos(angle), 0.0 },
                [_]T{    0.0      , 0.0,    0.0     , 1.0 },
            });

            return rotation.mul(self);
        }

        /// Produces a transformation that will rotate vectors by `angle`
        /// about the z-axis after the transformation applied by `self`.
        pub fn rotateZ(self: Self, angle: T) Self {
            const rotation = Matrix(T, 4).new([4][4]T{
                [_]T{@cos(angle), -@sin(angle), 0.0, 0.0 },
                [_]T{@sin(angle),  @cos(angle), 0.0, 0.0 },
                [_]T{   0.0     ,     0.0     , 1.0, 0.0 },
                [_]T{   0.0     ,     0.0     , 0.0, 1.0 },
            });

            return rotation.mul(self);
        }

        pub const ShearArgs = struct {
            xy: T = 0.0,
            xz: T = 0.0,
            yx: T = 0.0,
            yz: T = 0.0,
            zx: T = 0.0,
            zy: T = 0.0,
        };

        /// Produces a transformation that will shear vectors the values
        /// given in `args` after the transformation applied by `self`.
        ///
        /// If `args == .{ .xy = 3.0, .zx = -1.0 }`, for example, the shear
        /// will add `3.0` to x for each unit of y and `-1.0` to z for each
        /// unit of x.
        pub fn shear(self: Self, args: ShearArgs) Self {
            const shearing = Matrix(T, 4).new([4][4]T{
                [_]T{ 1.0    , args.xy, args.xz, 0.0 },
                [_]T{ args.yx, 1.0    , args.yz, 0.0 },
                [_]T{ args.zx, args.zy, 1.0    , 0.0 },
                [_]T{ 0.0    , 0.0    , 0.0    , 1.0 },
            });

            return shearing.mul(self);
        }

    };
}

test "Matrix creation" {
    const zero_matrix = Matrix(f32, 4).zero();

    const zeroes = [4][4]f32{
        [_]f32{ 0.0, 0.0, 0.0, 0.0 },
        [_]f32{ 0.0, 0.0, 0.0, 0.0 },
        [_]f32{ 0.0, 0.0, 0.0, 0.0 },
        [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    try testing.expect(zero_matrix.approxEqual(Matrix(f32, 4).new(zeroes)));

    const identity = Matrix(f32, 4).identity();

    const identity_data = [4][4]f32{
        [_]f32{ 1.0, 0.0, 0.0, 0.0 },
        [_]f32{ 0.0, 1.0, 0.0, 0.0 },
        [_]f32{ 0.0, 0.0, 1.0, 0.0 },
        [_]f32{ 0.0, 0.0, 0.0, 1.0 },
    };

    try testing.expect(identity.approxEqual(Matrix(f32, 4).new(identity_data)));
}

test "Matrix multiplication" {
    var a = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ 1.0, 2.0, 3.0, 4.0 },
        [_]f32{ 5.0, 6.0, 7.0, 8.0 },
        [_]f32{ 9.0, 8.0, 7.0, 6.0 },
        [_]f32{ 5.0, 4.0, 3.0, 2.0 },
    });

    const b = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ -2.0, 1.0, 2.0, 3.0 },
        [_]f32{ 3.0, 2.0, 1.0, -1.0 },
        [_]f32{ 4.0, 3.0, 6.0, 5.0 },
        [_]f32{ 1.0, 2.0, 7.0, 8.0 },
    });

    const axb = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ 20.0, 22.0, 50.0, 48.0 },
        [_]f32{ 44.0, 54.0, 114.0, 108.0 },
        [_]f32{ 40.0, 58.0, 110.0, 102.0 },
        [_]f32{ 16.0, 26.0, 46.0, 42.0 },
    });

    try testing.expect(a.mul(b).approxEqual(axb));

    a = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ 1.0, 2.0, 3.0, 4.0 },
        [_]f32{ 2.0, 4.0, 4.0, 2.0 },
        [_]f32{ 8.0, 6.0, 4.0, 1.0 },
        [_]f32{ 0.0, 0.0, 0.0, 1.0 },
    });

    const v = Tuple(f32).new(1.0, 2.0, 3.0, 1.0);
    const axv = Tuple(f32).new(18.0, 24.0, 33.0, 1.0);

    try testing.expect(a.tupleMul(v).approxEqual(axv));
}

test "Transpose" {
    const a = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ 0.0, 9.0, 3.0, 0.0 },
        [_]f32{ 9.0, 8.0, 0.0, 8.0 },
        [_]f32{ 1.0, 8.0, 5.0, 3.0 },
        [_]f32{ 0.0, 0.0, 5.0, 8.0 },
    });

    const a_transpose = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ 0.0, 9.0, 1.0, 0.0 },
        [_]f32{ 9.0, 8.0, 8.0, 0.0 },
        [_]f32{ 3.0, 0.0, 5.0, 5.0 },
        [_]f32{ 0.0, 8.0, 3.0, 8.0 },
    });

    try testing.expect(a.transpose().approxEqual(a_transpose));
    try testing.expect(Matrix(f32, 4).identity().transpose().approxEqual(Matrix(f32, 4).identity()));
}

test "Submatrices" {
    const a = Matrix(f32, 3).new([3][3]f32{
        [_]f32{ 1.0, 5.0, 0.0 },
        [_]f32{ -3.0, 2.0, 7.0 },
        [_]f32{ 0.0, 6.0, -3.0 },
    });

    const a_sub = Matrix(f32, 2).new([2][2]f32{
        [_]f32{ -3.0, 2.0 },
        [_]f32{ 0.0, 6.0 },
    });

    try testing.expect(a.submatrix(0, 2).approxEqual(a_sub));

    const b = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ -6.0, 1.0, 1.0, 6.0 },
        [_]f32{ -8.0, 5.0, 8.0, 6.0 },
        [_]f32{ -1.0, 0.0, 8.0, 2.0 },
        [_]f32{ -7.0, 1.0, -1.0, 1.0 },
    });

    const b_sub = Matrix(f32, 3).new([3][3]f32{
        [_]f32{ -6.0, 1.0, 6.0 },
        [_]f32{ -8.0, 8.0, 6.0 },
        [_]f32{ -7.0, -1.0, 1.0 },
    });

    try testing.expect(b.submatrix(2, 1).approxEqual(b_sub));
}

test "Cofactors and determinants" {
    const a = Matrix(f32, 3).new([3][3]f32{
        [_]f32{ 1.0, 2.0, 6.0 },
        [_]f32{ -5.0, 8.0, -4.0 },
        [_]f32{ 2.0, 6.0, 4.0 },
    });

    try testing.expectApproxEqAbs(a.cofactor(0, 0), 56.0, Matrix(f32, 3).tolerance);
    try testing.expectApproxEqAbs(a.cofactor(0, 1), 12.0, Matrix(f32, 3).tolerance);
    try testing.expectApproxEqAbs(a.cofactor(0, 2), -46.0, Matrix(f32, 3).tolerance);
    try testing.expectApproxEqAbs(a.det(), -196.0, Matrix(f32, 3).tolerance);

    const b = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ -2.0, -8.0, 3.0, 5.0 },
        [_]f32{ -3.0, 1.0, 7.0, 3.0 },
        [_]f32{ 1.0, 2.0, -9.0, 6.0 },
        [_]f32{ -6.0, 7.0, 7.0, -9.0 },
    });

    try testing.expectApproxEqAbs(b.cofactor(0, 0), 690.0, Matrix(f32, 4).tolerance);
    try testing.expectApproxEqAbs(b.cofactor(0, 1), 447.0, Matrix(f32, 4).tolerance);
    try testing.expectApproxEqAbs(b.cofactor(0, 2), 210.0, Matrix(f32, 4).tolerance);
    try testing.expectApproxEqAbs(b.cofactor(0, 3), 51.0, Matrix(f32, 4).tolerance);
    try testing.expectApproxEqAbs(b.det(), -4071.0, Matrix(f32, 4).tolerance);
}

test "Inversion" {
    const a = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ 8.0, -5.0, 9.0, 2.0 },
        [_]f32{ 7.0, 5.0, 6.0, 1.0 },
        [_]f32{ -6.0, 0.0, 9.0, 6.0 },
        [_]f32{ -3.0, 0.0, -9.0, -4.0 },
    });

    const a_inverse = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ -0.15385, -0.15385, -0.28205, -0.53846 },
        [_]f32{ -0.07692,  0.12308,  0.02564,  0.03077 },
        [_]f32{ 0.35897,  0.35897,  0.43590,  0.92308 },
        [_]f32{ -0.69231, -0.69231, -0.76923, -1.92308 },
    });

    try testing.expect((try a.inverse()).approxEqual(a_inverse));

    const b = Matrix(f32, 4).new([4][4]f32{
        [_]f32{  9.0,  3.0,  0.0,  9.0 },
        [_]f32{ -5.0, -2.0, -6.0, -3.0 },
        [_]f32{ -4.0,  9.0,  6.0,  4.0 },
        [_]f32{ -7.0,  6.0,  6.0,  2.0 },
    });

    const b_inverse = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ -0.04074, -0.07778,  0.14444, -0.22222 },
        [_]f32{ -0.07778,  0.03333,  0.36667, -0.33333 },
        [_]f32{ -0.02901, -0.14630, -0.10926,  0.12963 },
        [_]f32{  0.17778,  0.06667, -0.26667,  0.33333 },
    });

    try testing.expect((try b.inverse()).approxEqual(b_inverse));

    const c = Matrix(f32, 4).new([4][4]f32{
        [_]f32{  3.0, -9.0,  7.0,  3.0 },
        [_]f32{  3.0, -8.0,  2.0, -9.0 },
        [_]f32{ -4.0,  4.0,  4.0,  1.0 },
        [_]f32{ -6.0,  5.0, -1.0,  1.0 },
    });

    const d = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ 8.0,  2.0,  2.0,  2.0 },
        [_]f32{ 3.0, -1.0,  7.0,  0.0 },
        [_]f32{ 7.0,  0.0,  5.0,  4.0 },
        [_]f32{ 6.0, -2.0,  0.0,  5.0 },
    });

    try testing.expect(c.mul(d).mul(try d.inverse()).approxEqual(c));
}

test "Transformations" {
    // translation
    var transform = Matrix(f32, 4).identity().translate(5.0, -3.0, 2.0);
    var p = Tuple(f32).point(-3.0, 4.0, 5.0);

    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(2.0, 1.0, 7.0)));

    transform = try transform.inverse();
    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(-8, 7.0, 3.0)));

    var v = Tuple(f32).vec3(3.0, 4.0, 5.0);
    try testing.expect(transform.tupleMul(v).approxEqual(v));

    // scaling
    transform = Matrix(f32, 4).identity().scale(2.0, 3.0, 4.0);
    p = Tuple(f32).point(-4.0, 6.0, 8.0);

    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(-8.0, 18.0, 32.0)));

    v = Tuple(f32).vec3(-4.0, 6.0, 8.0);

    try testing.expect(transform.tupleMul(v).approxEqual(Tuple(f32).vec3(-8.0, 18.0, 32.0)));
    try testing.expect((try transform.inverse()).tupleMul(v).approxEqual(Tuple(f32).vec3(-2.0, 2.0, 2.0)));

    transform = Matrix(f32, 4).identity().scale(-1.0, 1.0, 1.0);
    p = Tuple(f32).point(2.0, 3.0, 4.0);

    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(-2.0, 3.0, 4.0)));

    // rotations
    transform = Matrix(f32, 4).identity().rotateX(pi / 4.0);
    p = Tuple(f32).point(0.0, 1.0, 0.0);

    try testing.expect(transform.tupleMul(p)
        .approxEqual(Tuple(f32).point(0.0, 1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0))));

    transform = transform.rotateX(pi / 4.0);
    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(0.0, 0.0, 1.0)));

    transform = Matrix(f32, 4).identity().rotateX(pi / 4.0);
    try testing.expect((try transform.inverse()).tupleMul(p)
        .approxEqual(Tuple(f32).point(0.0, 1.0 / @sqrt(2.0), -1.0 / @sqrt(2.0))));

    transform = Matrix(f32, 4).identity().rotateY(pi / 4.0);
    p = Tuple(f32).point(0.0, 0.0, 1.0);

    try testing.expect(transform.tupleMul(p)
        .approxEqual(Tuple(f32).point(1.0 / @sqrt(2.0), 0.0, 1.0 / @sqrt(2.0))));

    transform = transform.rotateY(pi / 4.0);

    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(1.0, 0.0, 0.0)));

    transform = Matrix(f32, 4).identity().rotateZ(pi / 4.0);
    p = Tuple(f32).point(0.0, 1.0, 0.0);

    try testing.expect(transform.tupleMul(p)
        .approxEqual(Tuple(f32).point(-1.0 / @sqrt(2.0), 1.0 / @sqrt(2.0), 0.0)));

    transform = transform.rotateZ(pi / 4.0);
    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(-1.0, 0.0, 0.0)));

    // shearing
    transform = Matrix(f32, 4).identity().shear(.{.xy = 1.0});
    p = Tuple(f32).point(2.0, 3.0, 4.0);

    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(5.0, 3.0, 4.0)));

    transform = Matrix(f32, 4).identity().shear(.{.xz = 1.0});
    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(6.0, 3.0, 4.0)));

    transform = Matrix(f32, 4).identity().shear(.{.yx = 1.0});
    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(2.0, 5.0, 4.0)));

    transform = Matrix(f32, 4).identity().shear(.{.yz = 1.0});
    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(2.0, 7.0, 4.0)));

    transform = Matrix(f32, 4).identity().shear(.{.zx = 1.0});
    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(2.0, 3.0, 6.0)));

    transform = Matrix(f32, 4).identity().shear(.{.zy = 1.0});
    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(2.0, 3.0, 7.0)));


    // chaining
    transform = Matrix(f32, 4).identity().rotateX(pi / 2.0).scale(5.0, 5.0, 5.0).translate(10.0, 5.0, 7.0);
    p = Tuple(f32).point(1.0, 0.0, 1.0);

    try testing.expect(transform.tupleMul(p).approxEqual(Tuple(f32).point(15.0, 0.0, 7.0)));
}

test "View transformation" {
    {
        const from = Tuple(f32).point(0.0, 0.0, 0.0);
        const to = Tuple(f32).point(0.0, 0.0, -1.0);
        const up = Tuple(f32).vec3(0.0, 1.0, 0.0);

        try testing.expect(
            Matrix(f32, 4)
                .viewTransform(from, to, up)
                .approxEqual(Matrix(f32, 4).identity())
        );
    }

    {
        const from = Tuple(f32).point(0.0, 0.0, 0.0);
        const to = Tuple(f32).point(0.0, 0.0, 1.0);
        const up = Tuple(f32).vec3(0.0, 1.0, 0.0);

        try testing.expect(
            Matrix(f32, 4)
                .viewTransform(from, to, up)
                .approxEqual(Matrix(f32, 4).identity().scale(-1.0, 1.0, -1.0))
        );

    }

    {
        const from = Tuple(f32).point(0.0, 0.0, 8.0);
        const to = Tuple(f32).point(0.0, 0.0, 0.0);
        const up = Tuple(f32).vec3(0.0, 1.0, 0.0);

        try testing.expect(
            Matrix(f32, 4)
                .viewTransform(from, to, up)
                .approxEqual(Matrix(f32, 4).identity().translate(0.0, 0.0, -8.0))
        );

    }

    {
        const from = Tuple(f32).point(1.0, 3.0, 2.0);
        const to = Tuple(f32).point(4.0, -2.0, 8.0);
        const up = Tuple(f32).vec3(1.0, 1.0, 0.0);

        const expected = Matrix(f32, 4).new([4][4]f32{
            [_]f32{ -0.50709, 0.50709,  0.67612, -2.36643 },
            [_]f32{  0.76772, 0.60609,  0.12122, -2.82843 },
            [_]f32{ -0.35857, 0.59761, -0.71714,  0.00000 },
            [_]f32{  0.00000, 0.00000,  0.00000,  1.00000 },
        });

        try testing.expect(
            Matrix(f32, 4)
                .viewTransform(from, to, up)
                .approxEqual(expected)
        );

    }
}

