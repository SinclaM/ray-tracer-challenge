# Ray Tracer Challenge

This project is a simple [Zig](https://ziglang.org/) implementation of the ray tracer described in
[The Ray Tracer Challenge](http://raytracerchallenge.com/).

You can find an interactive demo of this ray tracer online at [sinclam.github.io/ray-tracer-challenge](https://sinclam.github.io/ray-tracer-challenge).

<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/d27b09c6-e915-415a-a640-371e10fb9169 width=1200>

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
- [x] Bonus Chapter - Bounding boxes and hierarchies
- [x] Bonus Chapter - Texture mapping


## Examples

### Fresnel
<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/2a4709c2-ae44-4385-933a-fb9489edbc9e width=400>

### Patterns
<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/445e20cc-334a-460f-8073-6193b0d86661) width=800>

### Reflection and Refraction
<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/8c29e0ca-9f3c-4509-ac19-50e8f155913c width=800>

### Cubes
<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/e543b4ea-e6a3-4091-a9d6-8c9d3cc51487 width=800>

### Groups
<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/1a76dce9-9c63-41d8-a351-12b5931d5eab width=800>

### Teapot
<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/410f6d29-8b66-463c-a8f4-99ec79700a25 width=800>

Teapot model from [https://groups.csail.mit.edu/graphics/classes/6.837/F03/models/teapot.obj](https://groups.csail.mit.edu/graphics/classes/6.837/F03/models/teapot.obj).

### Dragons
<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/010d2169-6d18-460a-b630-ea21f41ec3db width=800>

Dragon model from [http://raytracerchallenge.com/bonus/assets/dragon.zip](http://raytracerchallenge.com/bonus/assets/dragon.zip).

### Nefertiti
<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/f1207f39-abed-4ccf-b7d2-8cc0bd073850 height=800>

Nefertiti bust model from [https://github.com/alecjacobson/common-3d-test-models/blob/master/data/nefertiti.obj](https://github.com/alecjacobson/common-3d-test-models/blob/master/data/nefertiti.obj).

### Earth
<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/673121c1-905e-4e6f-b6ca-e7eea75c24db width=800>

Earth texture from [https://planetpixelemporium.com/earth.html](https://planetpixelemporium.com/earth.html).

### Skybox
<img src=https://github.com/SinclaM/ray-tracer-challenge/assets/82351204/18d9d37d-a2f6-4e9e-a811-a0ecf5f8d69b width=800>

Lancellotti Chapel texture from [http://www.humus.name/index.php?page=Textures](http://www.humus.name/index.php?page=Textures).

## Building from source
To build for native:
```bash
zig build -Doptimize=ReleaseFast
```

To target the web (populating `www/` with the all the site's files):
```bash
zig build --sysroot ~/emsdk/upstream/emscripten -Dtarget=wasm32-emscripten -Doptimize=ReleaseFast
    && sed -i'' -e 's/_emscripten_return_address,/() => {},/g' www/ray-tracer-challenge.js
```

## Performance profiling

Although the ray tracer is not (yet) heavily optimized (e.g. it does not yet leverage Zig's SIMD builtins),
it is still very fast—faster in fact on a single thread than almost every other Ray Tracer Challenge implementation
on multiple threads I've compared with. And there is still significant room for optimization.

The optimizations I do make are largely informed by profilers. When built for native, the binary can be profiled with
`valgrind --tool=callgrind` and the results inspected with `qcachegrind`, which works well enough. Unfortunately,
[Valgrind's troubled state on macOS](https://www.reddit.com/r/cpp/comments/13n3tjt/i_find_its_not_possible_to_do_serious_cc_coding/),
combined with [Zig's incomplete Valgrind support](https://github.com/ziglang/zig/issues/1837), means profiling is not
always simple. For example, I've seen Valgrind erroneously run into `SIGILL` and the like. Using `std.heap.raw_c_allocator`
on native seems to fix most of these issues.

The ray tracer currently runs about 2x slower on WebAssembly than on native, which is reasonable. I use Firefox's
"performance" tab in the developer tools for profiling on the web.

I also use [hyperfine](https://github.com/sharkdp/hyperfine) for benchmarking.

## Benchmarks

Below are some benchmarks for scenes that can be found on the website. These benchmarks are not rigorously controlled
and averaged, but rather a general overview of speeds for various scenes. They may also change depending significantly
between Zig compiler versions. For example, I noticed a perfromance regression of up to 25% going from 0.11.0 to the
WIP 0.12.0 (perhaps related to [this similar issue](https://github.com/ziglang/zig/issues/17768)). The best way to
get a feel for the performance is to try things out yourself!

All benchmarks were done on a 2019 MacBook Pro (2.6Ghz, 6-Core Intel i7; 16GB RAM; macOS 12.6.7). WASM specific benchmarks
were done on Firefox 117 using 6 web workers (the maximum number of web workers Firefox will run in parallel, even on my
12 logical CPU system 🤷‍♂️). Native runs used 12 threads.

The 'WASM Preheated' category refers to renders done with the scene pre-built (scene description already parsed, objects
and bounding boxes already made, textures already loaded, etc.), which is supported on the site through the arrow key
camera movememnt. This preheating is irrelevant for simple scenes, but gives massive speedups for scenes that load
textures or construct BVHs.

Also note that renders on the website are periodically polled for completion. Renders may actually
complete up to 100ms before the reported time, which affects the benchmarks for very short renders.

| Scene                     | Resolution     | Native      | WASM       |   WASM Preheated   |
| ------------------------- | -------------- | ----------- | ---------- | ------------------ |
| Cover Scene               | 1280x1280      | 1.413 s     | 2.408 s    |  2.299 s           |
| Cubes                     | 600x300        | 0.225 s     | 0.418 s    |  0.407 s           |
| Cylinders                 | 800x400        | 0.111 s     | 0.221 s    |  0.109 s           |
| Reflection and Refraction | 400x200        | 0.113 s     | 0.213 s    |  0.205 s           |
| Fresnel                   | 600x600        | 0.283 s     | 0.429 s    |  0.411 s           |
| Groups                    | 600x200        | 0.091 s     | 0.217 s    |  0.202 s           |
| Teapot                    | 250x150        | 0.175 s     | 0.413 s    |  0.210 s           |
| Dragons                   | 500x200        | 6.957 s     | 12.663 s   |  2.492 s           |
| Nefertiti                 | 300x500        | 4.827 s     | 6.358 s    |  3.036 s           |
| Earth                     | 800x400        | 0.095 s     | 0.212 s    |  0.103 s           |
| Skybox[^1]                | 800x400        | 1.466 s     | 1.531 s    |  0.102 s           |
| Raytracer REPL Default    | 1280x720       | 0.210 s     | 0.220 s    |  0.209 s           |

## Other implementations
There are many great implementations of the Ray Tracer Challenge. At many points throughout the project, I referred to others
to verify my implementation, draw inspiration, or compare performance. I recommend you check out the following ray tracers:

* [graytracer](https://github.com/JarrodBegnoche/graytracer): fully-implemented, easy to setup, performant.
* [The Raytracer Challenge REPL](https://raytracer.xyz/): online demo with amazing site design.
* [RayTracerCPU](https://iliathoughts.com/posts/raytracer2/): very fast, helpful online demo.

## Known limitations
The website for this project uses the `SharedArrayBuffer` type, which may not be supported in some browsers (particurly,
Safari on iOS—even though [it is supposedly supported](https://caniuse.com/sharedarraybuffer)??). Use of `SharedArrayBuffer`
also requires certain HTTP headers to be set, which GitHub Pages does not support. To get around this, I use
[coi-serviceworker](https://github.com/gzuidhof/coi-serviceworker), which has the disadvantage of not working in
Private/Incognito sessions.
