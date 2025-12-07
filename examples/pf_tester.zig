const std = @import("std");
const mem = std.mem;

const zig_sc2 = @import("zig-sc2");
const bot_data = zig_sc2.bot_data;
const Actions = bot_data.Actions;
const GameInfo = bot_data.GameInfo;
const Bot = bot_data.Bot;
const Point2 = bot_data.Point2;
const Point3 = bot_data.Point3;
const unit_group = bot_data.unit_group;
const Unit = bot_data.Unit;
const UnitId = bot_data.UnitId;
const AbilityId = bot_data.AbilityId;
const InfluenceMap = bot_data.InfluenceMap;

const time = std.time;

const MyBot = struct {
    const Self = @This();

    allocator: mem.Allocator,
    arena: std.heap.ArenaAllocator,

    // These are mandatory
    name: []const u8,
    race: bot_data.Race,

    pub fn init(base_allocator: mem.Allocator) !Self {
        return .{
            .allocator = base_allocator,
            .arena = std.heap.ArenaAllocator.init(base_allocator),
            .name = "MyBot",
            .race = .terran,
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn onStart(
        self: *Self,
        bot: Bot,
        game_info: GameInfo,
        actions: *Actions,
    ) !void {
        defer _ = self.arena.reset(.retain_capacity);
        _ = actions;
        _ = bot;
        const arena = self.arena.allocator();
        var map = try InfluenceMap.fromGrid(arena, game_info.pathing_grid);

        const start_loc = game_info.start_location;
        const end_loc = game_info.enemy_start_locations[0];
        const times = 500;

        var timer = time.Timer.start() catch unreachable;
        _ = timer.lap();

        for (0..times) |_| {
            _ = try map.pathfindDirection(arena, start_loc, end_loc, false);
        }

        const pf_time = timer.lap();
        const pf_time_us: f64 = @as(f64, @floatFromInt(pf_time)) / (1E3 * times);
        std.debug.print("PF time avg: {}us\n", .{pf_time_us});
    }

    pub fn onStep(
        self: *Self,
        bot: Bot,
        game_info: GameInfo,
        actions: *Actions,
    ) !void {
        _ = bot;
        defer _ = self.arena.reset(.retain_capacity);

        const arena = self.arena.allocator();
        var map = try InfluenceMap.fromGrid(arena, game_info.pathing_grid);

        const start_loc = game_info.start_location;
        const end_loc = game_info.enemy_start_locations[0];

        const path = (try map.pathfindPath(arena, start_loc, end_loc, false)).?.path;
        const middle: usize = path.len / 2;
        map.addInfluence(path[middle], 20, 50, .none);
        const path2 = (try map.pathfindPath(arena, start_loc, end_loc, false)).?.path;

        for (map.grid, 0..) |val, i| {
            if (val > 1 and val < std.math.floatMax(f32)) {
                const p = map.indexToPoint(i).add(.{ .x = 0.5, .y = 0.5 });
                const z = game_info.getTerrainZ(p);

                actions.debugTextWorld(
                    "X",
                    Point3.fromPoint2(p, z),
                    .{ .r = 255, .g = 0, .b = 0 },
                    16,
                );
            }
        }
        for (path) |p| {
            const z = game_info.getTerrainZ(p);

            actions.debugTextWorld(
                "o",
                Point3.fromPoint2(p, z),
                .{ .r = 0, .g = 0, .b = 255 },
                16,
            );
        }
        for (path2) |p| {
            const z = game_info.getTerrainZ(p);

            actions.debugTextWorld(
                "o",
                Point3.fromPoint2(p, z),
                .{ .r = 0, .g = 255, .b = 0 },
                16,
            );
        }
    }

    pub fn onResult(
        self: *Self,
        bot: Bot,
        game_info: GameInfo,
        result: bot_data.Result,
    ) !void {
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

    _ = try zig_sc2.run(&my_bot, 2, gpa);
}
