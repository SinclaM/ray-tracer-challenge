const std = @import("std");
const print = std.debug.print;
const testing = std.testing;

const Tuple = @import("tuple.zig").Tuple;

const MatrixError = error { NotInvertible };

pub fn Matrix(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();
        const tolerance: T = 1e-5;

        data: [N][N]T,

        fn new(data: [N][N]T) Self {
            return .{ .data = data };
        }

        fn new_uninit() Self {
            const data: [N][N]T = undefined;
            return .{ .data = data };
        }

        fn zero() Self {
            var data: [N][N]T = undefined;
            for (data) |*row| {
                for (row) |*val| {
                    val.* = 0.0;
                }
            }
            return .{ .data = data };
        }

        fn identity() Self {
            var matrix = Self.zero();

            var i: usize = 0;
            while (i < N) {
                matrix.data[i][i] = 1.0;
                i += 1;
            }

            return matrix;
        }

        fn approx_equal(self: Self, other: Self) bool {
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

        fn mul(self: Self, other: Self) Self {
            var result = Self.new_uninit();
            var row: usize = 0;
            while (row < N) {
                var col: usize = 0;
                while (col < N) {
                    var i: usize = 0;
                    var sum: T = 0;
                    while (i < N) {
                        sum += self.data[row][i] * other.data[i][col];
                        i += 1;
                    }
                    result.data[row][col] = sum;
                    col += 1;
                }
                row += 1;
            }

            return result;
        }

        fn tupleMul(self: Self, tup: Tuple(T)) Tuple(T) {
            var result = Tuple(T).new(0.0, 0.0, 0.0, 0.0);

            var row = Tuple(T).from_buf(self.data[0]);
            result.x = row.dot(tup);

            row = Tuple(T).from_buf(self.data[1]);
            result.y = row.dot(tup);

            row = Tuple(T).from_buf(self.data[2]);
            result.z = row.dot(tup);

            row = Tuple(T).from_buf(self.data[3]);
            result.w = row.dot(tup);

            return result;
        }

        fn transpose(self: Self) Self {
            var transposed = Self.new_uninit();

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

        fn submatrix(self: Self, row: usize, col: usize) Matrix(T, N - 1) {
            var sub = Matrix(T, N - 1).new_uninit();

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

        fn minor(self: Self, row: usize, col: usize) T {
            return self.submatrix(row, col).det();
        }

        fn cofactor(self: Self, row: usize, col: usize) T {
            if ((row + col) % 2 == 0) {
                return self.minor(row, col);
            } else {
                return -self.minor(row, col);
            }
        }

        fn det(self: Self) T {
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

        fn inverse(self: Self) !Self {
            const det_ = self.det();
            if (@fabs(det_) < Self.tolerance) {
                return MatrixError.NotInvertible;
            }

            var inverse_ = Self.new_uninit();

            var row: usize = 0;
            while (row < N) : (row += 1) {
                var col: usize = 0;
                while (col < N) : (col += 1) {
                    inverse_.data[col][row] = self.cofactor(row, col) / det_;
                }
            }

            return inverse_;
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

    try testing.expect(zero_matrix.approx_equal(Matrix(f32, 4).new(zeroes)));

    const identity = Matrix(f32, 4).identity();

    const identity_data = [4][4]f32{
        [_]f32{ 1.0, 0.0, 0.0, 0.0 },
        [_]f32{ 0.0, 1.0, 0.0, 0.0 },
        [_]f32{ 0.0, 0.0, 1.0, 0.0 },
        [_]f32{ 0.0, 0.0, 0.0, 1.0 },
    };

    try testing.expect(identity.approx_equal(Matrix(f32, 4).new(identity_data)));
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

    try testing.expect(a.mul(b).approx_equal(axb));

    a = Matrix(f32, 4).new([4][4]f32{
        [_]f32{ 1.0, 2.0, 3.0, 4.0 },
        [_]f32{ 2.0, 4.0, 4.0, 2.0 },
        [_]f32{ 8.0, 6.0, 4.0, 1.0 },
        [_]f32{ 0.0, 0.0, 0.0, 1.0 },
    });

    const v = Tuple(f32).new(1.0, 2.0, 3.0, 1.0);
    const axv = Tuple(f32).new(18.0, 24.0, 33.0, 1.0);

    try testing.expect(a.tupleMul(v).approx_equal(axv));
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

    try testing.expect(a.transpose().approx_equal(a_transpose));
    try testing.expect(Matrix(f32, 4).identity().transpose().approx_equal(Matrix(f32, 4).identity()));
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

    try testing.expect(a.submatrix(0, 2).approx_equal(a_sub));

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

    try testing.expect(b.submatrix(2, 1).approx_equal(b_sub));
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

    try testing.expect((try a.inverse()).approx_equal(a_inverse));
}
