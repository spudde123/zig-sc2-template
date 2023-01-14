const std = @import("std");
const mem = std.mem;

const zig_sc2 = @import("zig-sc2");
const bot_data = zig_sc2.bot_data;
const unit_group = bot_data.unit_group;
const Unit = bot_data.Unit;
const UnitId = bot_data.UnitId;
const AbilityId = bot_data.AbilityId;


/// Your bot should be a struct with at least the fields
/// name and race. The only required functions are onStart,
/// onStep and onResult with function signatures as seen below.
const ExampleBot = struct {

    allocator: mem.Allocator,
    fba: std.heap.FixedBufferAllocator,
    // These are mandatory
    name: []const u8,
    race: bot_data.Race,

    pub fn init(base_allocator: mem.Allocator) !ExampleBot {
        var buffer = try base_allocator.alloc(u8, 10*1024*1024);
        var fba = std.heap.FixedBufferAllocator.init(buffer);
        
        return .{
            .allocator = base_allocator,
            .fba = fba,
            .name = "ExampleBot",
            .race = .terran,
        };
    }

    pub fn deinit(self: *ExampleBot) void {
        // Free memory here if required
        self.allocator.free(self.fba.buffer);
    }

    pub fn onStart(
        self: *ExampleBot,
        bot: bot_data.Bot,
        game_info: bot_data.GameInfo,
        actions: *bot_data.Actions
    ) void {
        _ = bot;
        _ = self;

        const enemy_start_location = game_info.enemy_start_locations[0];
        const start_location = game_info.start_location;
        std.debug.print("Start: {d} {d}\n", .{start_location.x, start_location.y});
        std.debug.print("Enemy: {d} {d}\n", .{enemy_start_location.x, enemy_start_location.y});
        actions.tagGame("TestingTag");
    }

    fn countReady(group: []Unit, unit_id: UnitId) usize {
        var count: usize = 0;
        for (group) |unit| {
            if (unit.unit_type == unit_id and unit.isReady()) count += 1;
        }
        return count;
    }

    fn produceUnits(self: ExampleBot, structures: []Unit, actions: *bot_data.Actions) void {
        _ = self;
        for (structures) |structure| {
            if (!structure.isReady() or structure.orders.len > 0) continue;
            switch (structure.unit_type) {
                .Barracks => {
                    actions.train(structure.tag, .Marine, false);
                },
                .Factory => {
                    actions.train(structure.tag, .SiegeTank, false);
                },
                .Starport => {
                    actions.train(structure.tag, .Liberator, false);
                },
                .CommandCenter, .OrbitalCommand, .PlanetaryFortress => {
                    actions.train(structure.tag, .SCV, false);
                },
                else => continue,
            }
        }
    } 

    pub fn onStep(
        self: *ExampleBot,
        bot: bot_data.Bot,
        game_info: bot_data.GameInfo,
        actions: *bot_data.Actions
    ) void {
        _ = self.fba.allocator();
        defer self.fba.reset();

        const own_units = bot.units.values();
        const main_base_ramp = game_info.getMainBaseRamp();
        const depot_count = countReady(own_units, UnitId.SupplyDepot) + bot.unitsPending(UnitId.SupplyDepot);
        const raxes_ready = countReady(own_units, UnitId.Barracks);
        const raxes_pending = bot.unitsPending(UnitId.Barracks);
        
        var can_place = actions.queryPlacement(UnitId.SupplyDepot, main_base_ramp.depot_first.?);
        
        var worker_iterator = unit_group.includeType(UnitId.SCV, own_units);
        if (can_place and bot.food_used >= 12 and bot.minerals >= 100 and depot_count == 0) {
            
            const res = worker_iterator.findClosest(main_base_ramp.depot_first.?).?;
            actions.build(res.unit.tag, UnitId.SupplyDepot, main_base_ramp.depot_first.?, false);
        }

        can_place = actions.queryPlacement(UnitId.SupplyDepot, main_base_ramp.depot_second.?);
        if (can_place and bot.food_used >= 12 and bot.minerals >= 100 and depot_count == 1) {
            const res = worker_iterator.findClosest(main_base_ramp.depot_second.?).?;
            actions.build(res.unit.tag, UnitId.SupplyDepot, main_base_ramp.depot_second.?, false);
        }

        can_place = actions.queryPlacement(UnitId.Barracks, main_base_ramp.barracks_middle.?);
        
        if (can_place and bot.food_used >= 12 and bot.minerals >= 150 and depot_count == 2 and raxes_ready + raxes_pending == 0) {
            const res = worker_iterator.findClosest(main_base_ramp.barracks_middle.?).?;    
            actions.build(res.unit.tag, UnitId.Barracks, main_base_ramp.barracks_middle.?, false);
        }

        var cc_iter = unit_group.includeType(UnitId.CommandCenter, own_units);
        if (raxes_ready == 1 and bot.minerals >= 150) {
            const first_cc = cc_iter.next();
            if (first_cc != null and first_cc.?.orders.len == 0) {
                actions.useAbility(first_cc.?.tag, AbilityId.UpgradeToOrbital_OrbitalCommand, false);
            }
        }
        self.produceUnits(own_units, actions);

        //if (bot.game_loop > 5500) actions.leaveGame();
    }

    pub fn onResult(
        self: *ExampleBot,
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
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_instance.allocator();
    defer _ = gpa_instance.deinit();

    var my_bot = try ExampleBot.init(gpa);
    defer my_bot.deinit();

    try zig_sc2.run(&my_bot, 2, gpa, .{});
}