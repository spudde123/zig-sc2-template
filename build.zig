const std = @import("std");
const fs = std.fs;

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
    var main_file: []const u8 = "src/main.zig";
    var bot_name: []const u8 = "zig-bot";
    var buf: [256]u8 = undefined;

    first_arg: {
        if (b.args) |args| {
            const file_to_test = std.fmt.bufPrint(&buf, "examples/{s}.zig", .{args[0]}) catch {
                std.log.err("Invalid example\n", .{});
                return;
            };

            const file = fs.cwd().openFile(file_to_test, .{}) catch {
                std.log.info("Building src/main.zig\n", .{});
                break :first_arg;
            };
            defer file.close();
            main_file = file_to_test;
            bot_name = args[0];
        }
    }

    const exe = b.addExecutable(bot_name, main_file);
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

    const exe_tests = b.addTest(main_file);
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
