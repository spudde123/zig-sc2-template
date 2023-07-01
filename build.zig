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
    const optimize = b.standardOptimizeOption(.{});

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

    const zig_sc2 = b.addModule("zig-sc2", .{ .source_file = .{ .path = "lib/zig-sc2/src/runner.zig" } });
    const exe = b.addExecutable(.{
        .name = bot_name,
        .root_source_file = .{ .path = main_file },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("zig-sc2", zig_sc2);
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
