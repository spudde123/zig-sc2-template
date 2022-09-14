const std = @import("std");
const mem = std.mem;

const zig_sc2 = @import("zig-sc2");
const bot_data = zig_sc2.bot_data;
const unit_group = bot_data.unit_group;
const Unit = bot_data.Unit;
const UnitId = bot_data.UnitId;


/// Your bot should be a struct with at least the fields
/// name and race. The only required functions are onStart,
/// onStep and onResult with function signatures as seen below.
const TestBot = struct {

    perm_alloc: mem.Allocator,
    step_alloc: mem.Allocator,

    // These are mandatory
    name: []const u8,
    race: bot_data.Race,

    pub fn init(perm_alloc: mem.Allocator, step_alloc: mem.Allocator) TestBot {
        return .{
            .perm_alloc = perm_alloc,
            .step_alloc = step_alloc,
            .name = "TestBot",
            .race = .terran,
        };
    }

    pub fn deinit(self: *TestBot) void {
        // Free memory here if required
        _ = self;
    }

    fn testFilter(unit: Unit, context: []UnitId) bool {
        for (context) |unit_id| {
            if(unit.unit_type == unit_id) return true;
        }
        return false;
    }

    pub fn onStart(
        self: *TestBot,
        bot: bot_data.Bot,
        game_info: bot_data.GameInfo,
        actions: *bot_data.Actions
    ) void {
        _ = self;
        _ = game_info;
        const enemy_start_location = game_info.enemy_start_locations[0];
        var context = [_]UnitId{UnitId.SCV};
        const res = unit_group.filter(bot.units, context[0..], testFilter, self.step_alloc);

        for (res) |u| {
            std.debug.print("{d} {d} {d}\n", .{u.tag, u.position.x, u.position.y});
        }
        for (bot.units) |unit| {
            if (unit.unit_type == bot_data.UnitId.SCV) {
                actions.attackPosition(unit.tag, enemy_start_location, false);
            }
        }
        
    }

    pub fn onStep(
        self: *TestBot,
        bot: bot_data.Bot,
        game_info: bot_data.GameInfo,
        actions: *bot_data.Actions
    ) void {
        _ = game_info;
        _ = self;
        if (bot.game_loop > 500) actions.leaveGame();
    }

    pub fn onResult(
        self: *TestBot,
        bot: bot_data.Bot,
        game_info: bot_data.GameInfo,
        result: bot_data.Result
    ) void {
        _ = bot;
        _ = game_info;
        _ = result;
        _ = self;
    }
    
};

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // Arena allocator that is freed at the end of the game
    const arena = arena_instance.allocator();
    defer arena_instance.deinit();

    // Fixed buffer which is reset at the end of each step
    var step_bytes = try arena.alloc(u8, 10*1024*1024);
    var fixed_buffer_instance = std.heap.FixedBufferAllocator.init(step_bytes);
    const fixed_buffer = fixed_buffer_instance.allocator();

    var my_bot = TestBot.init(arena, fixed_buffer);
    defer my_bot.deinit();

    try zig_sc2.run(&my_bot, 2, arena, .{});
}