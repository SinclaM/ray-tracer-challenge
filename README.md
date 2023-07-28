# Ray Tracer Challenge

This project is a simple [Zig](https://ziglang.org/) implementation of the ray tracer described in
[The Ray Tracer Challenge](http://raytracerchallenge.com/).

You can find an interactive demo of this ray tracer online at [sinclam.github.io/ray-tracer-challenge](https://sinclam.github.io/ray-tracer-challenge).

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/fc5406c2-5929-40a8-b3f1-6bacc19eb55e width=1200>

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
- [x] Chapter 12 - Cubes
- [x] Chapter 13 - Cylinders
- [x] Chapter 14 - Groups
- [x] Chapter 15 - Triangles
- [ ] Chapter 16 - Constructive Solid Geometry (CSG)
- [ ] Chapter 17 - Next Steps
- [x] A1 - Rendering the Cover Image
- [ ] Bonus Chapter - Rendering soft shadows
- [ ] Bonus Chapter - Bounding boxes and hierarchies
- [ ] Bonus Chapter - Texture mapping


## Examples

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/2a4709c2-ae44-4385-933a-fb9489edbc9e width=400>

<br/><br/>

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/445e20cc-334a-460f-8073-6193b0d86661) width=800> 

<br/><br/>

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/8c29e0ca-9f3c-4509-ac19-50e8f155913c width=800> 

<br/><br/>

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/e543b4ea-e6a3-4091-a9d6-8c9d3cc51487 width=800> 

<br/><br/>

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/1a76dce9-9c63-41d8-a351-12b5931d5eab width=800> 

<br/><br/>

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/410f6d29-8b66-463c-a8f4-99ec79700a25 width=800> 

<br/><br/>

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/99e74bd8-5caa-466c-beb9-7281bc60a397 width=800> 

## Performance profiling

Although the ray tracer is not (yet) heavily optimized (e.g. is does not yet leverage Zig's SIMD builtins),
it is still very fast—faster in fact on a single thread than almost every other Ray Tracer Challenge implementation
on multiple threads I've compared with. And there is still significant room for optimization.

The optimizations I do make are largely informed by profilers. When built for native, the binary can be profiled with
`valgrind --tool=callgrind` and the results inspected with `qcachegrind`, which works well enough. Unfortunately,
[Valgrind's troubled state on macOS](https://www.reddit.com/r/cpp/comments/13n3tjt/i_find_its_not_possible_to_do_serious_cc_coding/),
combined with [Zig's incomplete Valgrind support](https://github.com/ziglang/zig/issues/1837), means profiling is not
always simple. For example, I've seen Valgrind erroneously run into `SIGILL` and the like. Using `std.heap.raw_c_allocator`
seems to fix most of these issues.

The ray tracer currently runs about 2x slower on WebAssembly than on native, which is reasonable. I use Firefox's
"performance" tab in the developer tools for profiling on the web.

I also use [hyperfine](https://github.com/sharkdp/hyperfine) for benchmarking.
