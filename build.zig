const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    
    // If build is called `zig build -- example_bot`
    // we try to build example_bot.zig in the examples folder.
    // Otherwise default to src/main.zig
    var run_tests = true;
    const exe = e: {
        if (b.args) |args| {
            var buf: [256]u8 = undefined;
            const main_file = std.fmt.bufPrint(&buf, "examples/{s}.zig", .{args[0]}) catch {
                std.log.err("Invalid example\n", .{});
                return;
            };
            run_tests = false;
            break :e b.addExecutable(args[0], main_file);
        } else {
            break :e b.addExecutable("zig-bot", "src/main.zig");
        }
    };
    
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("zig-sc2", "lib/zig-sc2/src/runner.zig");
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    if (run_tests) {
        const exe_tests = b.addTest("src/main.zig");
        exe_tests.setTarget(target);
        exe_tests.setBuildMode(mode);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&exe_tests.step);
    }
}
