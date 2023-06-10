/// The floating point precision to use throughout the ray-tracer.
pub const F = f32;

/// The tolerance for floating point comparisons.
/// Two floats, f1 and f2, will be considered approximately equal
/// if |f1 - f2| < tolerance.
pub const tolerance: F = 1e-5;
