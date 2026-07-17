const std = @import("std");
const mem = std.mem;

const zig_sc2 = @import("zig-sc2");
const bot_data = zig_sc2.bot_data;
const Actions = bot_data.Actions;
const GameInfo = bot_data.GameInfo;
const Bot = bot_data.Bot;
const BotContext = zig_sc2.BotContext;
const Point2 = bot_data.Point2;
const unit_group = bot_data.unit_group;
const Unit = bot_data.Unit;
const UnitId = bot_data.UnitId;
const AbilityId = bot_data.AbilityId;

/// Your bot should be a struct with at least the fields
/// name and race. The only required functions are onStart,
/// onStep and onResult with function signatures as seen below.
const MyBot = struct {
    const Self = @This();

    allocator: mem.Allocator,

    // These are mandatory
    name: []const u8,
    race: bot_data.Race,

    pub fn init(base_allocator: mem.Allocator) !Self {
        return .{
            .allocator = base_allocator,
            .name = "MyBot",
            .race = .terran,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn onStart(
        self: *Self,
        ctx: BotContext,
    ) !void {
        _ = self;
        ctx.actions.tagGame("example_tag");
    }

    pub fn onStep(
        self: *Self,
        ctx: BotContext,
    ) !void {
        _ = self;
        if (ctx.bot.time >= 60) ctx.actions.leaveGame();
    }

    pub fn onResult(
        self: *Self,
        ctx: BotContext,
        result: bot_data.Result,
    ) !void {
        _ = self;
        _ = ctx;
        _ = result;
    }
};

pub fn main(init: std.process.Init) !void {
    var my_bot = try MyBot.init(init.gpa);
    defer my_bot.deinit();
    _ = try zig_sc2.run(&my_bot, .{
        .step_count = 2,
        .gpa = init.gpa,
        .arena = init.arena,
        .env_map = init.environ_map,
        .args = init.minimal.args,
        .io = init.io,
    });
}

test "bot_init" {
    const builtin = @import("builtin");
    // Run by setting the SC2 env var if it's in a non standard path
    var my_bot = try MyBot.init(std.testing.allocator);
    defer my_bot.deinit();
    var arena_instance = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_instance.allocator();
    defer arena_instance.deinit();

    try std.testing.expectEqualStrings("MyBot", my_bot.name);
    try std.testing.expect(my_bot.race == .terran);
    var env_map = try std.testing.environ.createMap(arena);
    // Dummy args so we don't crash
    const args: std.process.Args = if (builtin.os.tag == .windows)
        .{
            .vector = std.unicode.utf8ToUtf16LeStringLiteral(
                "runner_test",
            ),
        }
    else
        .{
            .vector = &[_][*:0]const u8{"runner_test"},
        };
    try std.testing.expect(.defeat == try zig_sc2.run(
        &my_bot,
        .{
            .step_count = 2,
            .gpa = std.testing.allocator,
            .arena = &arena_instance,
            .env_map = &env_map,
            .args = args,
            .io = std.testing.io,
        },
    ));
}
