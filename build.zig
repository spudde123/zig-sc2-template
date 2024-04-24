const std = @import("std");
const fs = std.fs;
const mem = std.mem;

pub fn build(b: *std.Build) void {
    const compile_log = std.log.scoped(.compilation);
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    // If build is called with `zig build -Dexample=example_bot`
    // we try to build example_bot.zig in the examples folder.
    // Otherwise default to src/main.zig
    var main_file: []const u8 = "src/main.zig";
    var bot_name: []const u8 = "zig-bot";
    var buf: [256]u8 = undefined;

    if (b.option([]const u8, "example", "Example name")) |example_name| {
        const file_to_test = std.fmt.bufPrint(&buf, "examples/{s}.zig", .{example_name}) catch {
            std.log.err("Invalid example\n", .{});
            return;
        };

        const file = fs.cwd().openFile(file_to_test, .{}) catch {
            std.log.err("Can't find example {s}\n", .{example_name});
            return;
        };
        defer file.close();
        main_file = file_to_test;
        bot_name = example_name;
    }

    compile_log.info("Building {s}\n", .{main_file});

    const zig_sc2 = b.addModule("zig-sc2", .{ .root_source_file = .{ .path = "lib/zig-sc2/src/runner.zig" } });
    const exe = b.addExecutable(.{
        .name = bot_name,
        .root_source_file = .{ .path = main_file },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zig-sc2", zig_sc2);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = main_file },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
