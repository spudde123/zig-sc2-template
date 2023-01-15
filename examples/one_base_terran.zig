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

// @TODO:
// 1. Optimize the build
// 2. Control units

const ArmyState = enum {
    defend,
    attack,
    search,
};

/// Your bot should be a struct with at least the fields
/// name and race. The only required functions are onStart,
/// onStep and onResult with function signatures as seen below.
const ExampleBot = struct {

    allocator: mem.Allocator,
    fba: std.heap.FixedBufferAllocator,
    // These are mandatory
    name: []const u8,
    race: bot_data.Race,

    build_step: u8 = 0,
    army_state: ArmyState = .defend,

    main_force: std.ArrayList(u64),
    new_army: std.ArrayList(u64),

    pub fn init(base_allocator: mem.Allocator) !ExampleBot {
        var buffer = try base_allocator.alloc(u8, 10*1024*1024);
        var fba = std.heap.FixedBufferAllocator.init(buffer);
        
        return .{
            .allocator = base_allocator,
            .fba = fba,
            .name = "ExampleBot",
            .race = .terran,
            .main_force = try std.ArrayList(u64).initCapacity(base_allocator, 60),
            .new_army = try std.ArrayList(u64).initCapacity(base_allocator, 30)
        };
    }

    pub fn deinit(self: *ExampleBot) void {
        self.main_force.deinit();
        self.new_army.deinit();
        self.allocator.free(self.fba.buffer);
    }

    pub fn onStart(
        self: *ExampleBot,
        bot: Bot,
        game_info: GameInfo,
        actions: *Actions
    ) void {
        _ = bot;
        _ = self;
        _ = game_info;

        actions.tagGame("TestingTag");
    }

    fn countReady(group: []Unit, unit_id: UnitId) usize {
        var count: usize = 0;
        for (group) |unit| {
            if (unit.unit_type == unit_id and unit.isReady()) count += 1;
        }
        return count;
    }

    fn findFreeGeysir(near: Point2, units: []Unit, geysirs: []Unit) Unit {
        var closest: Unit = undefined;
        var min_dist: f32 = std.math.f32_max;

        gl: for (geysirs) |geysir| {

            for (units) |unit| {
                if (unit.unit_type != .Refinery) continue;
                if (unit.position.distanceSquaredTo(geysir.position) < 1) continue :gl;
            }

            const dist = near.distanceSquaredTo(geysir.position);
            if (dist < min_dist) {
                closest = geysir;
                min_dist = dist;
            }
        }

        return closest;
    }

    fn runBuild(self: *ExampleBot, bot: Bot, game_info: GameInfo, actions: *Actions) void {
        const own_units = bot.units.values();
        //const enemy_units = bot.enemy_units.values();
        const main_base_ramp = game_info.getMainBaseRamp();
        
        switch (self.build_step) {
            0 => {
                if (bot.unitsPending(.SupplyDepot) == 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.food_used == 14 and bot.minerals >= 100) {
                    var worker_iterator = unit_group.includeType(.SCV, own_units);
            
                    if (worker_iterator.findClosest(main_base_ramp.depot_first.?)) |res| {
                        actions.build(res.unit.tag, .SupplyDepot, main_base_ramp.depot_first.?, false);
                    }
                }
            },
            1 => {
                if (bot.unitsPending(.Barracks) == 1) {
                    self.build_step += 1;
                    return;
                }

                const depots_ready = countReady(own_units, .SupplyDepot);
                if (bot.minerals >= 150 and depots_ready == 1) {
                    var worker_iterator = unit_group.includeType(.SCV, own_units);
            
                    if (worker_iterator.findClosest(main_base_ramp.barracks_with_addon.?)) |res| {
                        actions.build(res.unit.tag, .Barracks, main_base_ramp.barracks_with_addon.?, false);
                    }
                }
            },
            2 => {
                if (bot.unitsPending(.Refinery) == 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 75) {
                    var th_iterator = unit_group.includeType(.CommandCenter, own_units);
                    
                    if (th_iterator.next()) |th| {
                        const geysir = unit_group.findClosestUnit(bot.vespene_geysers, th.position);

                        var worker_iterator = unit_group.includeType(.SCV, own_units);
                        if (worker_iterator.findClosest(geysir.unit.position)) |res| {
                            actions.buildOnUnit(res.unit.tag, .Refinery, geysir.unit.tag, false);
                        }
                    }
                }
            },
            3 => {
                const count = countReady(own_units, .Refinery) + bot.unitsPending(.Refinery);
                if (count == 2) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 75) {
                    var th_iterator = unit_group.includeType(.CommandCenter, own_units);
                    
                    if (th_iterator.next()) |th| {
                        const geysir = findFreeGeysir(th.position, own_units, bot.vespene_geysers);

                        var worker_iterator = unit_group.includeType(.SCV, own_units);
                        if (worker_iterator.findClosestUsingAbility(geysir.position, .Harvest_Gather_SCV)) |res| {
                            actions.buildOnUnit(res.unit.tag, .Refinery, geysir.tag, false);
                        }
                    }
                }
            },
            4 => {
                if (bot.unitsPending(.OrbitalCommand) == 1) {
                    self.build_step += 1;
                    return;
                }

                const raxes_ready = countReady(own_units, .Barracks);

                if (raxes_ready == 1 and bot.minerals >= 150) {
                    var cc_iter = unit_group.includeType(.CommandCenter, own_units);
                    const first_cc = cc_iter.next();
                    if (first_cc != null and first_cc.?.orders.len == 0) {
                        actions.useAbility(first_cc.?.tag, .UpgradeToOrbital_OrbitalCommand, false);
                    }
                }
            },
            5 => {
                if (bot.unitsPending(.Factory) == 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 150 and bot.vespene >= 100) {
                    var worker_iterator = unit_group.includeType(.SCV, own_units);
                    const location_candidate = main_base_ramp.top_center.towards(game_info.start_location, 8);
                    if (actions.findPlacement(.Factory, location_candidate, 20)) |location| {
                        if (worker_iterator.findClosestUsingAbility(location, .Harvest_Gather_SCV)) |res| {
                            actions.build(res.unit.tag, .Factory, location, false);
                        }
                    }
                }
            },
            6 => {
                const count = countReady(own_units, .SupplyDepot) + countReady(own_units, .SupplyDepotLowered) + bot.unitsPending(.SupplyDepot);
                if (count == 2) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 100) {
                    var worker_iterator = unit_group.includeType(.SCV, own_units);
            
                    if (worker_iterator.findClosestUsingAbility(main_base_ramp.depot_second.?, .Harvest_Gather_SCV)) |res| {
                        actions.build(res.unit.tag, .SupplyDepot, main_base_ramp.depot_second.?, false);
                    }
                }
            },
            7 => {
                if (bot.unitsPending(.BarracksReactor) == 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 50 and bot.vespene >= 50) {
                    for (own_units) |unit| {
                        if (unit.unit_type != .Barracks or unit.orders.len > 0) continue;
                        actions.useAbility(unit.tag, .Build_Reactor_Barracks, false);
                    }
                }
            },
            8 => {
                if (bot.unitsPending(.Starport) == 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 150 and bot.vespene >= 100) {
                    var worker_iterator = unit_group.includeType(.SCV, own_units);
                    
                    const location_candidate = main_base_ramp.top_center.towards(main_base_ramp.bottom_center, -10);
                    if (actions.findPlacement(.Starport, location_candidate, 20)) |location| {
                        if (worker_iterator.findClosestUsingAbility(location, .Harvest_Gather_SCV)) |res| {
                            actions.build(res.unit.tag, .Starport, location, false);
                        }
                    }
                }
            },
            9 => {
                if (bot.unitsPending(.FactoryTechLab) == 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 50 and bot.vespene >= 25) {
                    for (own_units) |unit| {
                        if (unit.unit_type != .Factory or unit.orders.len > 0) continue;
                        actions.useAbility(unit.tag, .Build_TechLab_Factory, false);
                    }
                }
            },
            10 => {
                const count = countReady(own_units, .SupplyDepot) + countReady(own_units, .SupplyDepotLowered) + bot.unitsPending(.SupplyDepot);
                if (count == 3) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 100) {
                    var worker_iterator = unit_group.includeType(.SCV, own_units);
                    const location_candidate = game_info.start_location.towards(main_base_ramp.top_center, 5);
                    if (actions.findPlacement(.SupplyDepot, location_candidate, 20)) |location| {
                        if (worker_iterator.findClosestUsingAbility(location, .Harvest_Gather_SCV)) |res| {
                            actions.build(res.unit.tag, .SupplyDepot, location, false);
                        }
                    }
                }
            },
            else => {
                const supply_left = if (bot.food_used <= bot.food_cap) bot.food_cap - bot.food_used else 0;
                const depots_pending = bot.unitsPending(.SupplyDepot);
                if (bot.food_cap < 200 and bot.minerals >= 100 and (supply_left < 10 and depots_pending == 0) or (supply_left < 3 and depots_pending == 1)) {
                    var worker_iterator = unit_group.includeType(.SCV, own_units);
                    const location_candidate = game_info.start_location.towards(main_base_ramp.top_center, 5);
                    if (actions.findPlacement(.SupplyDepot, location_candidate, 20)) |location| {
                        if (worker_iterator.findClosestUsingAbility(location, .Harvest_Gather_SCV)) |res| {
                            actions.build(res.unit.tag, .SupplyDepot, location, false);
                        }
                    }
                }

                // If we have too many minerals build more raxes
                // one at a time
                if (bot.minerals >= 400 and bot.unitsPending(.Barracks) == 0) {
                    var worker_iterator = unit_group.includeType(.SCV, own_units);
                    
                    const location_candidate = main_base_ramp.top_center.towards(main_base_ramp.bottom_center, -15);
                    if (actions.findPlacement(.Barracks, location_candidate, 20)) |location| {
                        if (worker_iterator.findClosestUsingAbility(location, .Harvest_Gather_SCV)) |res| {
                            actions.build(res.unit.tag, .Barracks, location, false);
                        }
                    }
                }
            },
        }
    }

    fn produceUnits(bot: Bot, structures: []Unit, actions: *Actions) void {
        const reactors = [_]UnitId{.BarracksReactor, .FactoryReactor, .StarportReactor};

        for (structures) |structure| {
            if (!structure.isReady()) continue;

            var has_reactor = false;
            if (structure.addon_tag != 0) {
                has_reactor = r: {
                    const addon = bot.units.get(structure.addon_tag).?;
                    if (mem.indexOfScalar(UnitId, &reactors, addon.unit_type)) |_| {
                        break :r true;
                    }
                    break :r false;
                };
            }

            if ((!has_reactor and structure.orders.len > 0) or (has_reactor and structure.orders.len > 1)) continue;
            
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
                    const need_more = structure.ideal_harvesters - structure.assigned_harvesters >= 0;
                    if (need_more) actions.train(structure.tag, .SCV, false);
                },
                else => continue,
            }
        }
    }

    fn controlDepots(units: []Unit, enemies: []Unit, main_base_ramp: bot_data.Ramp, actions: *Actions) void {
        
        var close_enemies: usize = 0;
        for (enemies) |enemy| {
            if (enemy.position.distanceSquaredTo(main_base_ramp.top_center) < 36) close_enemies += 1;
        }

        for (units) |unit| {
            if (unit.build_progress >= 1 and unit.unit_type != .SupplyDepot and unit.unit_type != .SupplyDepotLowered) continue;
            const dist1 = unit.position.distanceSquaredTo(main_base_ramp.depot_first.?);
            const dist2 = unit.position.distanceSquaredTo(main_base_ramp.depot_second.?);

            if (dist1 > 1.5 and dist2 > 1.5) {
                if (unit.unit_type == .SupplyDepot) actions.useAbility(unit.tag, .Morph_SupplyDepot_Lower, false);
                continue;
            }

            if (close_enemies > 0 and unit.unit_type == .SupplyDepotLowered) {
                actions.useAbility(unit.tag, .Morph_SupplyDepot_Raise, false);
            } else if (close_enemies == 0 and unit.unit_type == .SupplyDepot) {
                actions.useAbility(unit.tag, .Morph_SupplyDepot_Lower, false);
            }
        }
    }

    fn rallyBuildings(bot: Bot, game_info: GameInfo, actions: *Actions) void {
        const main_base_ramp = game_info.getMainBaseRamp();
        for (bot.units_created) |new_unit_tag| {
            const unit = bot.units.get(new_unit_tag).?;
            if (unit.unit_type != .Barracks and unit.unit_type != .Factory and unit.unit_type != .Starport) continue;
            const target = main_base_ramp.top_center.towards(main_base_ramp.bottom_center, -4);
            actions.useAbilityOnPosition(unit.tag, .Smart, target, false);
        }
    }

    fn moveWorkersToGas(bot: Bot, actions: *Actions) void {
        const own_units = bot.units.values();
        for (own_units) |unit| {
            if (unit.unit_type != .Refinery or unit.build_progress < 1) continue;

            const needed_harvesters = unit.ideal_harvesters - unit.assigned_harvesters;
            if (needed_harvesters <= 0) continue;

            var worker_iterator = unit_group.includeType(.SCV, own_units);
            
            while (worker_iterator.next()) |worker| {
                if (worker.isUsingAbility(.Harvest_Gather_SCV)) {

                    const closest_mineral_info = unit_group.findClosestUnit(bot.mineral_patches, worker.position);
                    if (closest_mineral_info.distance_squared < 2) {
                        actions.useAbilityOnUnit(worker.tag, .Smart, unit.tag, false);
                        break;
                    }
                }
            }
        }
    }

    fn handleIdleWorkers(units: []Unit, minerals: []Unit, game_info: GameInfo, actions: *Actions) void {
        const closest_mineral_tag = unit_group.findClosestUnit(minerals, game_info.start_location).unit.tag;
        for (units) |unit| {
            if (unit.unit_type != .SCV or unit.orders.len > 0) continue;
            actions.useAbilityOnUnit(unit.tag, .Smart, closest_mineral_tag, false);
        }
    }

    fn useMules(units: []Unit, minerals: []Unit, actions: *Actions) void {
        for (units) |unit| {
            if (unit.unit_type != .OrbitalCommand or unit.build_progress < 1 or unit.energy < 50) continue;
            const closest_mineral_tag = unit_group.findClosestUnit(minerals, unit.position).unit.tag;
            actions.useAbilityOnUnit(unit.tag, .CalldownMULE_CalldownMULE, closest_mineral_tag, false);
        }
    }

    fn handleNewArmy(self: *ExampleBot, bot: Bot) void {
        const army_types = [_]UnitId{
            .Marine,
            .SiegeTank,
            .SiegeTankSieged,
            .Liberator,
            .LiberatorAG,
        };
        for (bot.units_created) |new_unit_tag| {
            const new_unit = bot.units.get(new_unit_tag).?;
            if (mem.indexOfScalar(UnitId, &army_types, new_unit.unit_type)) |_| {
                if (self.army_state == .attack) {
                    self.new_army.append(new_unit_tag) catch continue;
                } else {
                    self.main_force.append(new_unit_tag) catch continue;
                }
            }
        }
    }

    fn handleDeadUnits(self: *ExampleBot, dead_units: []u64) void {
        for (dead_units) |unit_tag| {
            if (mem.indexOfScalar(u64, self.main_force.items, unit_tag)) |index| {
                _ = self.main_force.swapRemove(index);
            }
            if (mem.indexOfScalar(u64, self.new_army.items, unit_tag)) |index| {
                _ = self.new_army.swapRemove(index);
            }
        }
    }

    fn isArmy(context: void, unit: Unit) bool {
        _ = context;
        return !unit.is_structure;
    }

    fn defend(self: *ExampleBot, bot: Bot, game_info: GameInfo, actions: *Actions) void {
        const main_base_ramp = game_info.getMainBaseRamp();
        const start_location = game_info.start_location;
        const rest_point = main_base_ramp.top_center.towards(main_base_ramp.bottom_center, -4);

        const enemy_units = bot.enemy_units.values();
        var army_iterator = unit_group.UnitIterator(void, isArmy){.buffer = enemy_units, .context = {}};
        
        if (army_iterator.findClosest(start_location)) |closest_info| {
            // If there is an enemy unit pretty close by we chase
            // after it with marines but leave tanks and liberators
            // near the ramp
            if (closest_info.distance_squared <= 400) {
                for (self.main_force.items) |unit_tag| {
                    const unit = bot.units.get(unit_tag).?;
                    if (unit.unit_type == .Marine) actions.attackPosition(unit_tag, closest_info.unit.position, false);
                }
                return;
            }
        }

        const middle_of_ramp = main_base_ramp.top_center.towards(main_base_ramp.bottom_center, 3);

        for (self.main_force.items) |unit_tag| {
            const unit = bot.units.get(unit_tag).?;
            if (unit.position.distanceSquaredTo(rest_point) >= 25) {
                switch (unit.unit_type) {
                    .SiegeTankSieged => actions.useAbility(unit_tag, .Unsiege_Unsiege, false),
                    .LiberatorAG => actions.useAbility(unit_tag, .Morph_LiberatorAAMode, false),
                    else => actions.attackPosition(unit_tag, rest_point, false),
                }
            } else {
                switch (unit.unit_type) {
                    .SiegeTank => actions.useAbility(unit_tag, .SiegeMode_SiegeMode, false),
                    .Liberator => actions.useAbilityOnPosition(unit_tag, AbilityId.Morph_LiberatorAGMode, middle_of_ramp, false),
                    else => continue,
                }
            }
        }
    }

    fn attack(self: *ExampleBot, bot: Bot, game_info: GameInfo, actions: *Actions) void {
        var army_center: Point2 = .{};
        for (self.main_force.items) |unit_tag| {
            const unit = bot.units.get(unit_tag).?;
            army_center = army_center.add(unit.position);
        }
        const unit_count = @intToFloat(f32, self.main_force.items.len);
        army_center.x = army_center.x / unit_count;
        army_center.y = army_center.y / unit_count;

        var i: usize = 0;
        while (i < self.new_army.items.len) {
            const unit_tag = self.new_army.items[i];
            const unit = bot.units.get(unit_tag).?;
            if (unit.position.distanceSquaredTo(army_center) < 125) {
                self.main_force.append(unit_tag) catch {
                    i += 1;
                    continue;
                };
                _ = self.new_army.swapRemove(i);
            } else {
                actions.attackPosition(unit_tag, army_center, false);
                i += 1;
            }
        }

        const target = t: {
            const enemy_units = bot.enemy_units.values();
            if (enemy_units.len == 0) break :t game_info.enemy_start_locations[0];

            const closest_enemy_info = unit_group.findClosestUnit(enemy_units, army_center);
            break :t closest_enemy_info.unit.position;
        };
        
        for (self.main_force.items) |unit_tag| {
            const unit = bot.units.get(unit_tag).?;
            switch (unit.unit_type) {
                .SiegeTankSieged => {
                    if (unit.position.distanceSquaredTo(target) > 140) {
                        actions.useAbility(unit_tag, .Unsiege_Unsiege, false);
                    }
                },
                .SiegeTank => {
                    if (unit.position.distanceSquaredTo(target) < 120) {
                        actions.useAbility(unit_tag, .SiegeMode_SiegeMode, false);
                    } else {
                        actions.attackPosition(unit_tag, target, false);
                    }
                },
                .LiberatorAG => {
                    if (unit.position.distanceSquaredTo(target) > 100) {
                        actions.useAbility(unit_tag, .Morph_LiberatorAAMode, false);
                    }
                },
                .Liberator => {
                    if (unit.position.distanceSquaredTo(target) < 60) {
                        const lib_target = unit.position.towards(target, 4);
                        actions.useAbilityOnPosition(unit_tag, .Morph_LiberatorAGMode, lib_target, false);
                    } else {
                        actions.attackPosition(unit_tag, target, false);
                    }
                },
                else => actions.attackPosition(unit_tag, target, false),
            }
        }
    }

    fn search(self: *ExampleBot, bot: Bot, game_info: GameInfo, actions: *Actions) void {
        _ = self;
        _ = bot;
        _ = game_info;
        _ = actions;
    }

    fn controlArmy(self: *ExampleBot, bot: Bot, game_info: GameInfo, actions: *Actions) void {
        const own_units = bot.units.values();
        //const enemy_units = bot.units.values();

        switch (self.army_state) {
            .defend => {
                const tank_types = [_]UnitId{.SiegeTank, .SiegeTankSieged};
                const tank_count = unit_group.amountOfTypes(own_units, &tank_types);
                const liberator_types = [_]UnitId{.Liberator, .LiberatorAG};
                const liberator_count = unit_group.amountOfTypes(own_units, &liberator_types);

                if (tank_count >= 2 and liberator_count >= 1) {
                    self.army_state = .attack;
                    return;
                }

                self.defend(bot, game_info, actions);
            },
            .attack => {
                if (self.main_force.items.len == 0) {
                    self.army_state = .defend;
                    self.main_force.appendSlice(self.new_army.items) catch {};
                    self.new_army.clearRetainingCapacity();
                    return;
                }

                self.attack(bot, game_info, actions);
            },
            .search => {
                self.search(bot, game_info, actions);
            },
        }
    }

    pub fn onStep(
        self: *ExampleBot,
        bot: Bot,
        game_info: GameInfo,
        actions: *Actions
    ) void {
        _ = self.fba.allocator();
        defer self.fba.reset();
        
        const own_units = bot.units.values();
        const enemy_units = bot.enemy_units.values();

        self.runBuild(bot, game_info, actions);
        rallyBuildings(bot, game_info, actions);
        moveWorkersToGas(bot, actions);
        handleIdleWorkers(own_units, bot.mineral_patches, game_info, actions);
        controlDepots(own_units, enemy_units, game_info.getMainBaseRamp(), actions);
        useMules(own_units, bot.mineral_patches, actions);
        produceUnits(bot, own_units, actions);

        self.handleDeadUnits(bot.dead_units);
        self.handleNewArmy(bot);
        self.controlArmy(bot, game_info, actions);
    }

    pub fn onResult(
        self: *ExampleBot,
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

    var my_bot = try ExampleBot.init(gpa);
    defer my_bot.deinit();

    try zig_sc2.run(&my_bot, 2, gpa, .{});
}