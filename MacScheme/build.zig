const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "MacScheme",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.addCSourceFiles(.{
        .files = &.{
            "src/main.m",
            "src/app_delegate.m",
            "src/scheme_text_grid.m",
            "src/vendor/macgui/ed_graphics_bridge.m",
            "src/vendor/macgui/aot_appkit_init.m",
            "src/basic_jit_stub.c",
            "src/runtime_compat_stubs.c",
        },
        .flags = &.{
            "-fobjc-arc",
            "-D_GNU_SOURCE",
        },
    });

    const grid_logic = b.addObject(.{
        .name = "grid_logic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/grid_logic.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.addObject(grid_logic);

    const macscheme_graphics = b.addObject(.{
        .name = "macscheme_graphics_runtime",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/macscheme_graphics_runtime.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.addObject(macscheme_graphics);

    const vendor_graphics_runtime = b.addObject(.{
        .name = "graphics_runtime",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/vendor/macgui/graphics_runtime.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.addObject(vendor_graphics_runtime);

    // Include directories
    exe.addIncludePath(b.path("chez"));
    exe.addIncludePath(b.path("src"));

    // Static libraries from Chez Scheme
    exe.addLibraryPath(b.path("lib"));
    exe.linkSystemLibrary("kernel"); // libkernel.a
    exe.linkSystemLibrary("z"); // libz.a
    exe.linkSystemLibrary("lz4"); // liblz4.a

    // Frameworks
    exe.linkFramework("AppKit");
    exe.linkFramework("Cocoa");
    exe.linkFramework("Metal");
    exe.linkFramework("MetalKit");
    exe.linkFramework("GameController");
    exe.linkFramework("CoreImage");
    exe.linkFramework("QuartzCore");
    exe.linkFramework("UniformTypeIdentifiers");

    // Dynamic libraries required by Chez Scheme
    exe.linkSystemLibrary("iconv");
    exe.linkSystemLibrary("ncurses");
    exe.linkSystemLibrary("m");
    exe.linkSystemLibrary("c");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.setCwd(b.path("."));
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
