# Ray Tracer Challenge

This project is a simple [Zig](https://ziglang.org/) implementation of the ray tracer described in
[The Ray Tracer Challenge](http://raytracerchallenge.com/).

## Status 

- [x] Chapter 1 - Tuples, Points, and Vectors
- [x] Chapter 2 - Drawing on a Canvas
- [x] Chapter 3 - Matrices
- [x] Chapter 4 - Matrix Transformations
- [x] Chapter 5 - Ray-Sphere Intersections
- [x] Chapter 6 - Light and Shading
- [x] Chapter 7 - Making a Scene
- [x] Chapter 8 - Shadows
- [x] Chapter 9 - Planes
- [x] Chapter 10 - Patterns
- [x] Chapter 11 - Reflection and Refraction
- [ ] Chapter 12 - Cubes
- [ ] Chapter 13 - Cylinders
- [ ] Chapter 14 - Groups
- [ ] Chapter 15 - Triangles
- [ ] Chapter 16 - Constructive Solid Geometry (CSG)
- [ ] Chapter 17 - Next Steps
- [ ] A1 - Rendering the Cover Image

## Examples

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/2a4709c2-ae44-4385-933a-fb9489edbc9e width=400>

<br/><br/>

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/445e20cc-334a-460f-8073-6193b0d86661) width=800> 

<br/><br/>

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/1a9eb6be-8081-434d-a0ec-6dad4cb1c309 width=800> 

## Performance profiling

Not much effort has (yet) been put into optimizations, although I do try to avoid unnecessary performance hits.
The ray tracer is not (yet) multithreaded and the small vector math library it uses does not (yet) leverage Zig's
SIMD builtins. Do not expect it to compete with a real ray tracer.

What optimizations I do make are largely informed by profilers. The binary is profiled with `valgrind --tool=callgrind`
and the results are inspected with `qcachegrind`, which works well enough.

Unfortunately, Zig does not have first-class profiler support in its current ecosystem.

I also use [hyperfine](https://github.com/sharkdp/hyperfine) for benchmarking.
