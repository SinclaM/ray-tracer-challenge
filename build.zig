const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    if (target.cpu_arch) |arch| {
        if (arch == std.Target.Cpu.Arch.wasm32) {
            const lib = b.addSharedLibrary(.{
                .name = "ray-tracer-challenge",
                .root_source_file = .{ .path = "src/lib.zig" },
                .target = target,
                .optimize = optimize,
            });
            lib.rdynamic = true;

            const install_lib = b.addInstallArtifact(
                lib, .{ .dest_dir = .{ .override = .{ .custom = "../www/" } } }
            );
            b.getInstallStep().dependOn(&install_lib.step);

            var www = std.fs.cwd().openDir("www", .{}) catch @panic("Can't access www!");
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
                var scenes_src = std.fs.cwd().openDir("scenes", .{}) catch @panic("Can't access scenes!");
                defer scenes_src.close();

                var scenes_dest = www.openDir("scenes", .{}) catch @panic("Can't access www/scenes!");
                defer scenes_dest.close();

                var iter_scenes = std.fs.cwd().openIterableDir("scenes", .{})
                    catch @panic("Can't access scenes for iteration!");
                defer iter_scenes.close();

                var iter = iter_scenes.iterate();
                while (true) {
                    const entry = iter.next() catch @panic("Can't iterate through scenes!");
                    if (entry == null) {
                        break;
                    } else {
                        switch (entry.?.kind) {
                            .file => scenes_src.copyFile(entry.?.name, scenes_dest, entry.?.name, .{})
                                catch @panic("Can't copy scene!"),
                            else => {},
                        }
                    }
                }
            }

            {
                // Copy all the data files into www
                var data_src = std.fs.cwd().openDir("data", .{}) catch @panic("Can't access data!");
                defer data_src.close();

                var data_dest = www.openDir("data", .{}) catch @panic("Can't access www/data!");
                defer data_dest.close();

                var iter_data = std.fs.cwd().openIterableDir("data", .{})
                    catch @panic("Can't access data for iteration!");
                defer iter_data.close();

                var iter = iter_data.iterate();
                while (true) {
                    const entry = iter.next() catch @panic("Can't iterate through data!");
                    if (entry == null) {
                        break;
                    } else {
                        switch (entry.?.kind) {
                            .file => data_src.copyFile(entry.?.name, data_dest, entry.?.name, .{})
                                catch @panic("Can't copy data!"),
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

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

