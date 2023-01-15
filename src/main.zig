const std = @import("std");
const mem = std.mem;

const zig_sc2 = @import("zig-sc2");
const bot_data = zig_sc2.bot_data;
const Actions = bot_data.Actions;
const GameInfo = bot_data.GameInfo;
const Bot = bot_data.Bot;
const Point2 = bot_data.Point2;
const unit_group = bot_data.unit_group;
const Unit = bot_data.Unit;
const UnitId = bot_data.UnitId;
const AbilityId = bot_data.AbilityId;

/// Your bot should be a struct with at least the fields
/// name and race. The only required functions are onStart,
/// onStep and onResult with function signatures as seen below.
const MyBot = struct {

    allocator: mem.Allocator,

    // These are mandatory
    name: []const u8,
    race: bot_data.Race,

    pub fn init(base_allocator: mem.Allocator) !MyBot {
        return .{
            .allocator = base_allocator,
            .name = "MyBot",
            .race = .terran,
        };
    }

    pub fn deinit(self: *MyBot) void {
       _ = self;
    }

    pub fn onStart(
        self: *MyBot,
        bot: Bot,
        game_info: GameInfo,
        actions: *Actions
    ) void {
        _ = bot;
        _ = self;
        _ = game_info;
        actions.tagGame("example_tag");
    }

    pub fn onStep(
        self: *MyBot,
        bot: Bot,
        game_info: GameInfo,
        actions: *Actions
    ) void {
       _ = self;
       _ = game_info;
       if (bot.time >= 60) actions.leaveGame();
    }

    pub fn onResult(
        self: *MyBot,
        bot: Bot,
        game_info: GameInfo,
        result: bot_data.Result
    ) void {
        _ = bot;
        _ = game_info;
        _ = result;
        _ = self;
    }
    
};

pub fn main() !void {
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_instance.allocator();
    defer _ = gpa_instance.deinit();

    var my_bot = try MyBot.init(gpa);
    defer my_bot.deinit();

    try zig_sc2.run(&my_bot, 2, gpa, .{});
}