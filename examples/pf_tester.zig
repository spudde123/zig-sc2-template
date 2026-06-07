const std = @import("std");
const mem = std.mem;

const zig_sc2 = @import("zig-sc2");
const BotContext = zig_sc2.BotContext;
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
    io: std.Io,

    // These are mandatory
    name: []const u8,
    race: bot_data.Race,

    pub fn init(base_allocator: mem.Allocator, io: std.Io) !Self {
        return .{
            .allocator = base_allocator,
            .arena = std.heap.ArenaAllocator.init(base_allocator),
            .io = io,
            .name = "MyBot",
            .race = .terran,
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn onStart(
        self: *Self,
        ctx: BotContext,
    ) !void {
        defer _ = self.arena.reset(.retain_capacity);
        const arena = self.arena.allocator();
        var map = try InfluenceMap.fromGrid(arena, ctx.game_info.pathing_grid, ctx.game_info.terrain_height);

        const start_loc = ctx.game_info.start_location;
        const end_loc = ctx.game_info.enemy_start_locations[0];
        const times = 500;

        const start = std.Io.Timestamp.now(self.io, .awake);

        for (0..times) |_| {
            _ = try map.pathfindDirection(arena, start_loc, end_loc, .{});
        }

        const elapsed = start.untilNow(self.io, .awake);
        std.debug.print("PF time avg: {}us\n", .{@as(f64, @floatFromInt(elapsed.toMicroseconds())) / @as(f64, @floatFromInt(times))});
    }

    pub fn onStep(
        self: *Self,
        ctx: BotContext,
    ) !void {
        defer _ = self.arena.reset(.retain_capacity);

        const arena = self.arena.allocator();
        var map = try InfluenceMap.fromGrid(arena, ctx.game_info.pathing_grid, ctx.game_info.terrain_height);

        const start_loc = ctx.game_info.start_location;
        const end_loc = ctx.game_info.enemy_start_locations[0];

        const path = (try map.pathfindPath(arena, start_loc, end_loc, .{})).?.path;
        const middle: usize = path.len / 2;
        map.addInfluence(path[middle], 20, 50, .none);
        const path2 = (try map.pathfindPath(arena, start_loc, end_loc, .{})).?.path;

        for (map.grid, 0..) |val, i| {
            if (val > 1 and val < std.math.floatMax(f32)) {
                const p = map.indexToPoint(i).add(.{ .x = 0.5, .y = 0.5 });
                const z = ctx.game_info.getTerrainZ(p);

                ctx.actions.debugTextWorld(
                    "X",
                    Point3.fromPoint2(p, z),
                    .{ .r = 255, .g = 0, .b = 0 },
                    16,
                );
            }
        }
        for (path) |p| {
            const z = ctx.game_info.getTerrainZ(p);

            ctx.actions.debugTextWorld(
                "o",
                Point3.fromPoint2(p, z),
                .{ .r = 0, .g = 0, .b = 255 },
                16,
            );
        }
        for (path2) |p| {
            const z = ctx.game_info.getTerrainZ(p);

            ctx.actions.debugTextWorld(
                "o",
                Point3.fromPoint2(p, z),
                .{ .r = 0, .g = 255, .b = 0 },
                16,
            );
        }
    }

    pub fn onResult(
        self: *Self,
        ctx: BotContext,
        result: bot_data.Result,
    ) !void {
        _ = ctx;
        _ = result;
        _ = self;
    }
};

pub fn main(init: std.process.Init) !void {
    var my_bot = try MyBot.init(init.gpa, init.io);
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
