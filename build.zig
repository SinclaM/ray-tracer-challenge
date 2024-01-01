const std = @import("std");
const builtin = @import("builtin");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const zigimg = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    if (target.cpu_arch) |arch| {
        if (arch == std.Target.Cpu.Arch.wasm32) {
            const lib = b.addStaticLibrary(.{
                .name = "lib",
                .root_source_file = .{ .path = "src/lib.zig" },
                .target = .{
                    .cpu_arch = .wasm32,
                    .cpu_model = .{ .explicit = &std.Target.wasm.cpu.mvp },
                    .cpu_features_add = std.Target.wasm.featureSet(&.{ .atomics, .bulk_memory, .simd128 }),
                    .os_tag = .emscripten,
                },
                .optimize = optimize,
                .link_libc = true
            });
            lib.shared_memory = true;
            lib.single_threaded = false;
            lib.bundle_compiler_rt = true;

            lib.addModule("zigimg", zigimg.module("zigimg"));

            if (b.sysroot == null) {
                @panic("pass '--sysroot \"[path to emsdk]/upstream/emscripten\"'");
            }

            const emccExe = switch (builtin.os.tag) {
                .windows => "emcc.bat",
                else => "emcc",
            };
            var emcc_run_arg = try b.allocator.alloc(
                u8,
                b.sysroot.?.len + emccExe.len + 1
            );
            defer b.allocator.free(emcc_run_arg);

            emcc_run_arg = try std.fmt.bufPrint(
                emcc_run_arg,
                "{s}" ++ std.fs.path.sep_str ++ "{s}",
                .{ b.sysroot.?, emccExe }
            );

            const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_run_arg});
            emcc_command.addFileArg(lib.getEmittedBin());
            emcc_command.step.dependOn(&lib.step);
            emcc_command.addArgs(&[_][]const u8{
                "-o",
                "www" ++ std.fs.path.sep_str ++ "ray-tracer-challenge.js",
                "--embed-file",
                "data@/",
                "--no-entry",
                "-pthread",
                "-sPTHREAD_POOL_SIZE=navigator.hardwareConcurrency",
                "-sINITIAL_MEMORY=167772160",
                "-sALLOW_MEMORY_GROWTH",
                "-sEXPORTED_FUNCTIONS=_startInitRenderer,_tryFinishInitRenderer,_initRendererIsOk,_initRendererGetPixels,_initRendererGetWidth,_initRendererGetHeight,_initRendererGetErr,_deinitRenderer,_startRender,_tryFinishRender,_rotateCamera,_moveCamera",
                "-sEXPORTED_RUNTIME_METHODS=ccall,cwrap",
                "-sSTACK_SIZE=10485760", // Increase stack size to 10MB
                "-sALLOW_BLOCKING_ON_MAIN_THREAD=1",
                "-O3",
                //"-sUSE_OFFSET_CONVERTER",
            });
            b.getInstallStep().dependOn(&emcc_command.step);

            var www = try std.fs.cwd().openDir("www", .{});
            defer www.close();

            www.makeDir("scenes") catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => @panic("Unable to create www/scenes!")
            };

            www.makeDir("data") catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => @panic("Unable to create www/scenes!")
            };

            {
                // Copy all the scene descriptions into www
                var scenes_src = try std.fs.cwd().openDir("scenes", .{});
                defer scenes_src.close();

                var scenes_dest = try www.openDir("scenes", .{});
                defer scenes_dest.close();

                var iter_scenes = try std.fs.cwd().openDir("scenes", .{ .iterate = true});
                defer iter_scenes.close();

                var iter = iter_scenes.iterate();
                while (true) {
                    const entry = try iter.next();
                    if (entry == null) {
                        break;
                    } else {
                        switch (entry.?.kind) {
                            .file => try scenes_src.copyFile(entry.?.name, scenes_dest, entry.?.name, .{}),
                            else => {},
                        }
                    }
                }
            }

            {
                // Copy all the data files into www
                var data_src = try std.fs.cwd().openDir("data", .{});
                defer data_src.close();

                var data_dest = try www.openDir("data", .{});
                defer data_dest.close();

                var iter_data = try std.fs.cwd().openDir("data", .{ .iterate = true });
                defer iter_data.close();

                var iter = iter_data.iterate();
                while (true) {
                    const entry = try iter.next();
                    if (entry == null) {
                        break;
                    } else {
                        switch (entry.?.kind) {
                            .file => try data_src.copyFile(entry.?.name, data_dest, entry.?.name, .{}),
                            else => {},
                        }
                    }
                }
            }
        }
    } else {
        const exe = b.addExecutable(.{
            .name = "ray-tracer-challenge",
            // In this case the main source file is merely a path, however, in more
            // complicated build scripts, this could be a generated file.
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });

        exe.addModule("zigimg", zigimg.module("zigimg"));

        // This declares intent for the executable to be installed into the
        // standard location when the user invokes the "install" step (the default
        // step when running `zig build`).
        b.installArtifact(exe);

        // This *creates* a Run step in the build graph, to be executed when another
        // step is evaluated that depends on it. The next line below will establish
        // such a dependency.
        const run_cmd = b.addRunArtifact(exe);

        // By making the run step depend on the install step, it will be run from the
        // installation directory rather than directly from within the cache directory.
        // This is not necessary, however, if the application depends on other installed
        // files, this ensures they will be present and in the expected location.
        run_cmd.step.dependOn(b.getInstallStep());

        // This allows the user to pass arguments to the application in the build
        // command itself, like this: `zig build run -- arg1 arg2 etc`
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        // This creates a build step. It will be visible in the `zig build --help` menu,
        // and can be selected like this: `zig build run`
        // This will evaluate the `run` step rather than the default, which is "install".
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

    }

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });

    unit_tests.addModule("zigimg", zigimg.module("zigimg"));

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

