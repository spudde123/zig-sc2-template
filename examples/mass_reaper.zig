const std = @import("std");
const mem = std.mem;
const math = std.math;

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
const InfluenceMap = bot_data.InfluenceMap;

const reaper_grenade_range = 5;
const heal_at_less_than = 0.5;
const range_buffer = 3;
const reaper_range = 5;
const second_attack_limit = 22.4 * 0.79 * 0.8;

/// Done very quick and dirty, intention is to test
/// the influence map functions with reapers
/// Largely follows a Python Reaper example by
/// rasper https://github.com/spudde123/SC2MapAnalysis/tree/develop/examples/MassReaper
const MassReaper = struct {
    const Self = @This();

    allocator: mem.Allocator,
    fba: std.heap.FixedBufferAllocator,
    // These are mandatory
    name: []const u8,
    race: bot_data.Race,

    build_step: u8 = 0,
    reaper_map: InfluenceMap = .{},

    pub fn init(base_allocator: mem.Allocator) !Self {
        var buffer = try base_allocator.alloc(u8, 5*1024*1024);
        return .{
            .allocator = base_allocator,
            .fba = std.heap.FixedBufferAllocator.init(buffer),
            .name = "ReaperBot",
            .race = .terran,
        };
    }

    pub fn deinit(self: *Self) void {
        self.reaper_map.deinit(self.allocator);
        self.allocator.free(self.fba.buffer);
    }

    fn closerToStart(context: Point2, lhs: Point2, rhs: Point2) bool {
        return context.distanceSquaredTo(lhs) < context.distanceSquaredTo(rhs);
    }

    pub fn onStart(
        self: *Self,
        bot: Bot,
        game_info: GameInfo,
        actions: *Actions
    ) !void {
        _ = bot;
        _ = actions;
        std.sort.sort(Point2, game_info.expansion_locations, game_info.start_location, closerToStart);
        self.reaper_map = try InfluenceMap.fromGrid(self.allocator, game_info.reaper_grid, game_info.terrain_height);
        std.debug.print("Start: {d} {d}\n", .{game_info.start_location.x, game_info.start_location.y});
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

    fn runBuild(self: *Self, bot: Bot, game_info: GameInfo, actions: *Actions) void {
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
            
                    if (worker_iterator.findClosest(main_base_ramp.barracks_middle.?)) |res| {
                        actions.build(res.unit.tag, .Barracks, main_base_ramp.barracks_middle.?, false);
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
                        const geysir = unit_group.findClosestUnit(bot.vespene_geysers, th.position) orelse return;

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
                if (countReady(own_units, .Barracks) + bot.unitsPending(.Barracks) == 2) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 150) {
                    var worker_iterator = unit_group.includeType(.SCV, own_units);
                    const location_candidate = main_base_ramp.top_center.towards(game_info.start_location, 8);
                    if (actions.findPlacement(.Barracks, location_candidate, 20)) |location| {
                        if (worker_iterator.findClosestUsingAbility(location, .Harvest_Gather_SCV)) |res| {
                            actions.build(res.unit.tag, .Barracks, location, false);
                        }
                    }
                }
            },
            5 => {
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

                const th_types = [_]UnitId{.CommandCenter, .OrbitalCommand};
                const ths = unit_group.amountOfTypes(own_units, &th_types);
                const max_barracks: usize = if (ths == 1) 4 else 7;
                const current_count = countReady(own_units, .Barracks) + bot.unitsPending(.Barracks);
                // If we have too many minerals build more raxes
                // one at a time
                if (bot.minerals >= 150 and current_count < max_barracks) {
                    var worker_iterator = unit_group.includeType(.SCV, own_units);
                    
                    const location_candidate = main_base_ramp.top_center.towards(main_base_ramp.bottom_center, -15);
                    if (actions.findPlacement(.Barracks, location_candidate, 20)) |location| {
                        if (worker_iterator.findClosestUsingAbility(location, .Harvest_Gather_SCV)) |res| {
                            actions.build(res.unit.tag, .Barracks, location, false);
                        }
                    }
                }

                const ths_pending = bot.unitsPending(.CommandCenter);
                if (bot.minerals >= 400 and ths < 2 and ths_pending == 0) {
                    var worker_iterator = unit_group.includeType(.SCV, own_units);
                    if (worker_iterator.findClosestUsingAbility(game_info.expansion_locations[1], .Harvest_Gather_SCV)) |res| {
                        actions.build(res.unit.tag, .CommandCenter, game_info.expansion_locations[1], false);
                    }
                }

                const refinery_count = countReady(own_units, .Refinery) + bot.unitsPending(.Refinery);

                for (own_units) |unit| {
                    if (unit.build_progress < 1 or (unit.unit_type != .CommandCenter and unit.unit_type != .OrbitalCommand)) continue;
                    if (bot.minerals >= 150 and unit.unit_type == .CommandCenter) {
                        actions.useAbility(unit.tag, .UpgradeToOrbital_OrbitalCommand, false);
                    }

                    if (ths == 2 and bot.minerals >= 75 and refinery_count < 4) {
                        const geysir = findFreeGeysir(unit.position, own_units, bot.vespene_geysers);

                        var worker_iterator = unit_group.includeType(.SCV, own_units);
                        if (worker_iterator.findClosestUsingAbility(geysir.position, .Harvest_Gather_SCV)) |res| {
                            actions.buildOnUnit(res.unit.tag, .Refinery, geysir.tag, false);
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

            const has_reactor = r: {
                if (structure.addon_tag == 0) break :r false;
                const addon = bot.units.get(structure.addon_tag).?;
                if (mem.indexOfScalar(UnitId, &reactors, addon.unit_type)) |_| {
                    break :r true;
                }
                break :r false;
            };

            if ((!has_reactor and structure.orders.len > 0) or (has_reactor and structure.orders.len > 1)) continue;
            
            switch (structure.unit_type) {
                .Barracks => {
                    if (bot.minerals >= 50 and bot.vespene >= 50) actions.train(structure.tag, .Reaper, false);
                },
                .CommandCenter, .OrbitalCommand, .PlanetaryFortress => {
                    const need_more = structure.ideal_harvesters - structure.assigned_harvesters >= 0;
                    if (need_more and bot.minerals >= 50) actions.train(structure.tag, .SCV, false);
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
            if (unit.build_progress < 1 or (unit.unit_type != .SupplyDepot and unit.unit_type != .SupplyDepotLowered)) continue;
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
            switch (unit.unit_type) {
                .Barracks => {
                    const target = main_base_ramp.top_center.towards(main_base_ramp.bottom_center, -7);
                    actions.useAbilityOnPosition(unit.tag, .Smart, target, false);
                },
                .CommandCenter => {
                    const closest_mineral_res = unit_group.findClosestUnit(bot.mineral_patches, unit.position).?;
                    actions.useAbilityOnUnit(unit.tag, .Smart, closest_mineral_res.unit.tag, false);
                },
                else => {},
            }
        }
    }

    fn moveWorkersToGas(bot: Bot, actions: *Actions) void {
        const own_units = bot.units.values();
        for (own_units) |unit| {
            if (unit.unit_type != .Refinery or unit.build_progress < 1) continue;

            const needed_harvesters = unit.ideal_harvesters - unit.assigned_harvesters;
            var worker_iterator = unit_group.includeType(.SCV, own_units);
            
            if (needed_harvesters > 0) {
                while (worker_iterator.next()) |worker| {
                    if (worker.isUsingAbility(.Harvest_Gather_SCV)) {

                        const closest_mineral_info = unit_group.findClosestUnit(bot.mineral_patches, worker.position) orelse return;
                        if (closest_mineral_info.distance_squared < 2) {
                            actions.useAbilityOnUnit(worker.tag, .Smart, unit.tag, false);
                            break;
                        }
                    }
                }
            } else if (needed_harvesters < 0) {
                while (worker_iterator.next()) |worker| {
                    if (worker.orders.len == 0) continue;
                    if (worker.orders[0].ability_id == .Harvest_Gather_SCV and worker.orders[0].target.tag == unit.tag) {
                        const closest_mineral_info = unit_group.findClosestUnit(bot.mineral_patches, worker.position) orelse return;
                        actions.useAbilityOnUnit(worker.tag, .Smart, closest_mineral_info.unit.tag, false);
                        break;
                    }
                }
            }
        }
    }

    fn handleIdleWorkers(units: []Unit, minerals: []Unit, game_info: GameInfo, actions: *Actions) void {
        const closest_mineral_res = unit_group.findClosestUnit(minerals, game_info.start_location) orelse return;
        const closest_mineral_tag = closest_mineral_res.unit.tag;
        for (units) |unit| {
            if (unit.unit_type != .SCV or unit.orders.len > 0) continue;
            actions.useAbilityOnUnit(unit.tag, .Smart, closest_mineral_tag, false);
        }
    }

    fn useMules(units: []Unit, minerals: []Unit, actions: *Actions) void {
        for (units) |unit| {
            if (unit.unit_type != .OrbitalCommand or unit.build_progress < 1 or unit.energy < 50) continue;
            const closest_mineral_res = unit_group.findClosestUnit(minerals, unit.position) orelse continue;
            const closest_mineral_tag = closest_mineral_res.unit.tag;
            actions.useAbilityOnUnit(unit.tag, .CalldownMULE_CalldownMULE, closest_mineral_tag, false);
        }
    }

    fn isArmy(context: void, unit: Unit) bool {
        _ = context;
        return !unit.is_structure;
    }

    fn relevantEnemy(context: Point2, unit: Unit) bool {
        const army = !unit.is_structure;
        const close = context.distanceSquaredTo(unit.position) < 15*15;
        return !unit.is_flying and army and close;
    }

    fn updateReaperGrid(self: *Self, bot: Bot, game_info: GameInfo, actions: *Actions) void {
        self.reaper_map.reset(game_info.reaper_grid);
        const enemy_units = bot.enemy_units.values();
        for (enemy_units) |unit| {
            if (unit.build_progress < 1) continue;

            const unit_data = actions.game_data.units.get(unit.unit_type).?;
            const ground_range = unit_data.ground_range;
            const ground_dps = unit_data.ground_dps;
            if (ground_range != 0 and ground_dps != 0) {
                self.reaper_map.addInfluence(unit.position, ground_range + range_buffer, ground_dps, .none);
            }
        }
    }

    fn getAttackTarget(bot: Bot, game_info: GameInfo) Point2 {
        if (bot.time > 300) {
            var closest_unit: ?Unit = null;
            var min_unit_dist: f32 = math.f32_max;
            var closest_struct: ?Unit = null;
            var min_struct_dist: f32 = math.f32_max;

            const enemy_units = bot.enemy_units.values();
            for (enemy_units) |unit| {
                const dist = unit.position.distanceSquaredTo(game_info.start_location);
                if (unit.is_structure) {
                    if (dist < min_struct_dist) {
                        closest_struct = unit;
                        min_struct_dist = dist;
                    }
                } else {
                    if (!unit.is_flying and !unit.is_hallucination and unit.cloak != .cloaked and dist < min_unit_dist) {
                        closest_unit = unit;
                        min_unit_dist = dist;
                    }
                }
            }

            if (closest_unit) |u| {
                return u.position;
            }

            if (closest_struct) |s| {
                return s.position;
            }
        }

        return game_info.enemy_start_locations[0];
    }

    fn moveToSafety(self: *Self, game_info: GameInfo, actions: *Actions, unit: Unit, allocator: mem.Allocator) void {
        const safe_spot = self.reaper_map.findClosestSafeSpot(unit.position, 15) orelse game_info.start_location;
        if (self.reaper_map.pathfindDirection(allocator, unit.position, safe_spot, false)) |dir| {
            actions.moveToPosition(unit.tag, dir.next_point, false);
        } else {
            actions.moveToPosition(unit.tag, game_info.start_location, false);
        }

    }

    fn controlArmy(self: *Self, bot: Bot, game_info: GameInfo, actions: *Actions) void {
        const own_units = bot.units.values();
        const enemy_units = bot.enemy_units.values();
        const heal_spot = self.reaper_map.findClosestSafeSpot(game_info.getMapCenter(), 15) orelse game_info.start_location;
        const attack_target = getAttackTarget(bot, game_info);
        
        const fb = self.fba.allocator();
        defer self.fba.reset();

        for (own_units) |unit| {
            if (unit.unit_type != .Reaper or unit.weapon_cooldown > second_attack_limit) continue;
            // Doing this here because it seems with reapers near some map corners
            // we are in a wall according to the grid. Probably because
            // the resolution of the pathing grid isn't high enough and reapers
            // are pretty small units?
            const valid_pos = self.reaper_map.validateEndPoint(unit.position) orelse continue;

            if (unit.health / unit.health_max < heal_at_less_than) {
                if (self.reaper_map.pathfindDirection(fb, valid_pos, heal_spot, false)) |dir| {
                    actions.moveToPosition(unit.tag, dir.next_point, false);
                } else {
                    actions.moveToPosition(unit.tag, game_info.start_location, false);
                }
                continue;
            }

            var enemy_iterator = unit_group.UnitIterator(Point2, relevantEnemy){.buffer = enemy_units, .context = unit.position};
            var found_in_range = false;
            var lowest_health: f32 = math.f32_max;
            var target: ?Unit = null;
            while (enemy_iterator.next()) |enemy| {
                const in_range = enemy.position.distanceSquaredTo(unit.position) < reaper_range*reaper_range;
                if (in_range) {
                    if (!found_in_range or enemy.health + enemy.shield < lowest_health) {
                        lowest_health = enemy.health + enemy.shield;
                        target = enemy;
                    }
                    found_in_range = true;
                } else if (!found_in_range) {
                    if (enemy.health + enemy.shield < lowest_health) {
                        lowest_health = enemy.health + enemy.shield;
                        target = enemy;
                    }
                }
            }

            if (target) |target_unit| {
                if (unit.weapon_cooldown == 0) {
                    actions.attackUnit(unit.tag, target_unit.tag, false);
                    continue;
                }
            } 

            if (self.reaper_map.grid[self.reaper_map.pointToIndex(valid_pos)] > 1) {
                self.moveToSafety(game_info, actions, unit, fb);
                continue;
            }

            if (unit.position.distanceSquaredTo(attack_target) > 5*5) {
                // Only do pathfinding if close enemies exist
                if (enemy_iterator.exists()) {
                    if (self.reaper_map.pathfindDirection(fb, valid_pos, attack_target, false)) |pf| {
                        actions.moveToPosition(unit.tag, pf.next_point, false);
                        continue;
                    }
                }
                actions.moveToPosition(unit.tag, attack_target, false);
            } 
            
            actions.attackPosition(unit.tag, attack_target, false);
        }
    }

    pub fn onStep(
        self: *Self,
        bot: Bot,
        game_info: GameInfo,
        actions: *Actions
    ) !void {

        const own_units = bot.units.values();
        const enemy_units = bot.enemy_units.values();

        self.runBuild(bot, game_info, actions);
        rallyBuildings(bot, game_info, actions);
        moveWorkersToGas(bot, actions);
        handleIdleWorkers(own_units, bot.mineral_patches, game_info, actions);
        controlDepots(own_units, enemy_units, game_info.getMainBaseRamp(), actions);
        useMules(own_units, bot.mineral_patches, actions);
        produceUnits(bot, own_units, actions);

        self.updateReaperGrid(bot, game_info, actions);
        self.controlArmy(bot, game_info, actions);
    }

    pub fn onResult(
        self: *Self,
        bot: Bot,
        game_info: GameInfo,
        result: bot_data.Result
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

    var my_bot = try MassReaper.init(gpa);
    defer my_bot.deinit();

    try zig_sc2.run(&my_bot, 2, gpa, .{});
}