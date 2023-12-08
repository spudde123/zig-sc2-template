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
const BuffId = bot_data.BuffId;
const Prng = std.rand.DefaultPrng;

const ProtossBot = struct {
    const Self = @This();

    allocator: mem.Allocator,
    prng: Prng,
    build_step: u8 = 0,

    // These are mandatory
    name: []const u8,
    race: bot_data.Race,

    pub fn init(base_allocator: mem.Allocator) !Self {
        return .{
            .allocator = base_allocator,
            .name = "ProtossBot",
            .race = .protoss,
            .prng = std.rand.DefaultPrng.init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    fn randomNear(self: *Self, point: Point2, distance: f32) Point2 {
        const sin: f32 = -1 + 2 * self.prng.random().float(f32);
        const cos: f32 = -1 + 2 * self.prng.random().float(f32);
        const p = Point2{ .x = cos, .y = sin };
        return point.add(p.multiply(distance));
    }

    fn closerToStart(context: Point2, lhs: Point2, rhs: Point2) bool {
        return context.distanceSquaredTo(lhs) < context.distanceSquaredTo(rhs);
    }

    fn countReady(group: []Unit, unit_id: UnitId) usize {
        var count: usize = 0;
        for (group) |unit| {
            if (unit.unit_type == unit_id and unit.isReady()) count += 1;
        }
        return count;
    }

    fn findFreeGeysir(near: Point2, units: []Unit, geysirs: []Unit) ?Unit {
        var closest: ?Unit = null;
        var min_dist: f32 = 12 * 12;

        gl: for (geysirs) |geysir| {
            for (units) |unit| {
                if (unit.unit_type != .Assimilator) continue;
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
        const main_base_ramp = game_info.getMainBaseRamp();

        switch (self.build_step) {
            0 => {
                if (bot.unitsPending(.Pylon) == 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.food_used >= 14 and bot.minerals >= 100) {
                    var worker_iterator = unit_group.includeType(.Probe, own_units);

                    if (worker_iterator.findClosest(main_base_ramp.depot_first.?)) |res| {
                        actions.build(res.unit.tag, .Pylon, main_base_ramp.depot_first.?, false);
                    }
                }
            },
            1 => {
                if (bot.unitsPending(.Gateway) == 1) {
                    self.build_step += 1;
                    return;
                }

                const depots_ready = countReady(own_units, .Pylon);
                if (bot.minerals >= 150 and depots_ready == 1) {
                    var worker_iterator = unit_group.includeType(.Probe, own_units);

                    if (worker_iterator.findClosest(main_base_ramp.barracks_middle.?)) |res| {
                        actions.build(res.unit.tag, .Gateway, main_base_ramp.barracks_middle.?, false);
                    }
                }
            },
            2 => {
                if (bot.unitsPending(.Assimilator) == 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 75) {
                    var th_iterator = unit_group.includeType(.Nexus, own_units);

                    if (th_iterator.next()) |th| {
                        const geysir = unit_group.findClosestUnit(bot.vespene_geysers, th.position) orelse return;

                        var worker_iterator = unit_group.includeType(.Probe, own_units);
                        if (worker_iterator.findClosest(geysir.unit.position)) |res| {
                            actions.buildOnUnit(res.unit.tag, .Assimilator, geysir.unit.tag, false);
                        }
                    }
                }
            },
            3 => {
                if (bot.unitsPending(.Nexus) == 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 400) {
                    var worker_iterator = unit_group.includeType(.Probe, own_units);
                    if (worker_iterator.findClosestUsingAbility(game_info.expansion_locations[1], .Harvest_Gather_Probe)) |res| {
                        actions.build(res.unit.tag, .Nexus, game_info.expansion_locations[1], false);
                    }
                }
            },
            4 => {
                if (bot.unitsPending(.Pylon) == 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 100) {
                    var worker_iterator = unit_group.includeType(.Probe, own_units);

                    const location_candidate = main_base_ramp.top_center.towards(main_base_ramp.bottom_center, -15);
                    if (actions.findPlacement(.Pylon, location_candidate, 20)) |location| {
                        if (worker_iterator.findClosestUsingAbility(location, .Harvest_Gather_Probe)) |res| {
                            actions.build(res.unit.tag, .Pylon, location, false);
                        }
                    }
                }
            },
            5 => {
                if (bot.unitsPending(.CyberneticsCore) == 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 150) {
                    var worker_iterator = unit_group.includeType(.Probe, own_units);
                    const location_candidate = main_base_ramp.top_center.towards(game_info.start_location, 8);
                    if (actions.findPlacement(.CyberneticsCore, location_candidate, 20)) |location| {
                        if (worker_iterator.findClosestUsingAbility(location, .Harvest_Gather_Probe)) |res| {
                            actions.build(res.unit.tag, .CyberneticsCore, location, false);
                        }
                    }
                }
            },
            6 => {
                const count = countReady(own_units, .Assimilator) + bot.unitsPending(.Assimilator);
                if (count == 2) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 75) {
                    var th_iterator = unit_group.includeType(.Nexus, own_units);
                    const th = th_iterator.findClosest(game_info.start_location).?.unit;

                    const geysir = findFreeGeysir(th.position, own_units, bot.vespene_geysers).?;

                    var worker_iterator = unit_group.includeType(.Probe, own_units);
                    if (worker_iterator.findClosestUsingAbility(geysir.position, .Harvest_Gather_Probe)) |res| {
                        actions.buildOnUnit(res.unit.tag, .Assimilator, geysir.tag, false);
                    }
                }
            },
            else => {
                const supply_left = if (bot.food_used <= bot.food_cap) bot.food_cap - bot.food_used else 0;
                const pylons_pending = bot.unitsPending(.Pylon);
                if (bot.food_cap < 200 and bot.minerals >= 100 and (supply_left < 10 and pylons_pending == 0) or (supply_left < 3 and pylons_pending == 1)) {
                    var worker_iterator = unit_group.includeType(.Probe, own_units);
                    const location_candidate = game_info.start_location.towards(main_base_ramp.top_center, 5);
                    if (actions.findPlacement(.Pylon, location_candidate, 20)) |location| {
                        if (worker_iterator.findClosestUsingAbility(location, .Harvest_Gather_Probe)) |res| {
                            actions.build(res.unit.tag, .Pylon, location, false);
                        }
                    }
                }

                const gateways_ready = countReady(own_units, .Gateway) + countReady(own_units, .WarpGate);
                const gateways_pending = bot.unitsPending(.Gateway) + bot.unitsPending(.WarpGate);
                if (bot.minerals >= 150 and gateways_ready + gateways_pending < 4) {
                    var worker_iterator = unit_group.includeType(.Probe, own_units);

                    const location_candidate = main_base_ramp.top_center.towards(main_base_ramp.bottom_center, -15);

                    if (actions.findPlacement(.Gateway, location_candidate, 20)) |location| {
                        if (worker_iterator.findClosestUsingAbility(location, .Harvest_Gather_Probe)) |res| {
                            actions.build(res.unit.tag, .Gateway, location, false);
                        }
                    }
                }
            },
        }
    }

    fn rallyBuildings(bot: Bot, actions: *Actions) void {
        for (bot.units_created) |new_unit_tag| {
            const unit = bot.units.get(new_unit_tag).?;
            if (unit.unit_type == .Nexus) {
                const closest_mineral_res = unit_group.findClosestUnit(bot.mineral_patches, unit.position).?;
                actions.useAbilityOnUnit(unit.tag, .Smart, closest_mineral_res.unit.tag, false);
            }
        }
    }

    fn doUpgrades(bot: Bot, actions: *Actions) void {
        const own_units = bot.units.values();
        const warpgate_status = bot.upgradePending(.WarpGateResearch);
        for (own_units) |unit| {
            switch (unit.unit_type) {
                .CyberneticsCore => {
                    if (bot.minerals >= 50 and bot.vespene >= 50 and warpgate_status == 0) {
                        actions.useAbility(unit.tag, .Research_WarpGate, false);
                    }
                },
                .Gateway => {
                    if (warpgate_status >= 1 and unit.orders.len == 0) {
                        actions.useAbility(unit.tag, .Morph_WarpGate, false);
                    }
                },
                else => continue,
            }
        }
    }

    fn produceUnits(self: *Self, bot: Bot, game_info: GameInfo, actions: *Actions) void {
        const ramp_top = game_info.getMainBaseRamp().top_center;
        const structures = bot.units.values();
        for (structures) |structure| {
            if (!structure.isReady() or structure.orders.len > 0) continue;

            switch (structure.unit_type) {
                .Gateway => {
                    if (bot.minerals >= 125 and bot.vespene >= 50) {
                        actions.train(structure.tag, .Stalker, false);
                    } else if (bot.minerals >= 100) actions.train(structure.tag, .Zealot, false);
                },
                .WarpGate => {
                    const warpin_pos = self.randomNear(ramp_top, 4);
                    if (bot.minerals >= 125 and bot.vespene >= 50 and structure.hasAbilityAvailable(.WarpGateTrain_Stalker)) {
                        if (actions.findPlacementForAbility(.WarpGateTrain_Stalker, warpin_pos, 25)) |pos| {
                            actions.useAbilityOnPosition(structure.tag, .WarpGateTrain_Stalker, pos, false);
                        }
                    } else if (bot.minerals >= 100 and structure.hasAbilityAvailable(.WarpGateTrain_Zealot)) {
                        if (actions.findPlacementForAbility(.WarpGateTrain_Zealot, warpin_pos, 25)) |pos| {
                            actions.useAbilityOnPosition(structure.tag, .WarpGateTrain_Zealot, pos, false);
                        }
                    }
                },
                .Nexus => {
                    const need_more = structure.ideal_harvesters - structure.assigned_harvesters >= 0;
                    if (need_more and bot.minerals >= 50) actions.train(structure.tag, .Probe, false);
                },
                else => continue,
            }
        }
    }

    fn moveWorkersToGas(bot: Bot, actions: *Actions) void {
        const own_units = bot.units.values();
        for (own_units) |unit| {
            if (unit.unit_type != .Assimilator or unit.build_progress < 1) continue;

            const needed_harvesters = unit.ideal_harvesters - unit.assigned_harvesters;
            var worker_iterator = unit_group.includeType(.Probe, own_units);

            if (needed_harvesters > 0) {
                while (worker_iterator.next()) |worker| {
                    if (worker.isUsingAbility(.Harvest_Gather_Probe)) {
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
                    if (worker.orders[0].ability_id == .Harvest_Gather_Probe and worker.orders[0].target.tag == unit.tag) {
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
            if (unit.unit_type != .Probe or unit.orders.len > 0) continue;
            actions.useAbilityOnUnit(unit.tag, .Smart, closest_mineral_tag, false);
        }
    }

    fn useChronoboost(bot: Bot, actions: *Actions) void {
        const units = bot.units.values();
        const warpgate_status = bot.upgradePending(.WarpGateResearch);
        for (units) |unit| {
            if (unit.unit_type != .Nexus or unit.build_progress < 1 or unit.energy < 50) continue;

            if (warpgate_status > 0 and warpgate_status < 1) {
                var cybercore_iter = unit_group.includeType(.CyberneticsCore, units);
                const cybercore = cybercore_iter.next().?;
                if (!cybercore.hasBuff(.ChronoBoostEnergyCost)) {
                    actions.useAbilityOnUnit(unit.tag, .Effect_ChronoBoostEnergyCost, cybercore.tag, false);
                    continue;
                }
            }

            if (!unit.hasBuff(.ChronoBoostEnergyCost)) {
                actions.useAbilityOnUnit(unit.tag, .Effect_ChronoBoostEnergyCost, unit.tag, false);
            }
        }
    }

    fn defend(units: []Unit, enemies: []Unit, game_info: GameInfo, actions: *Actions) void {
        const closest_unit_info = unit_group.findClosestUnit(enemies, game_info.start_location);
        const ramp_top = game_info.getMainBaseRamp().top_center;
        for (units) |unit| {
            switch (unit.unit_type) {
                .Zealot, .Stalker => {
                    if (closest_unit_info) |info| {
                        if (info.distance_squared < 40 * 40) {
                            actions.attackPosition(unit.tag, info.unit.position, false);
                        } else {
                            if (unit.position.distanceSquaredTo(ramp_top) > 25) {
                                actions.moveToPosition(unit.tag, ramp_top, false);
                            }
                        }
                    }
                },
                else => continue,
            }
        }
    }

    fn attack(units: []Unit, enemies: []Unit, game_info: GameInfo, actions: *Actions) void {
        _ = enemies;
        for (units) |unit| {
            switch (unit.unit_type) {
                .Zealot, .Stalker => {
                    actions.attackPosition(unit.tag, game_info.enemy_start_locations[0], false);
                },
                else => continue,
            }
        }
    }

    fn controlArmy(bot: Bot, game_info: GameInfo, actions: *Actions) void {
        const own_units = bot.units.values();
        const enemy_units = bot.enemy_units.values();

        if (bot.time < 360) {
            defend(own_units, enemy_units, game_info, actions);
        } else {
            attack(own_units, enemy_units, game_info, actions);
        }
    }

    pub fn onStart(
        self: *Self,
        bot: Bot,
        game_info: GameInfo,
        actions: *Actions,
    ) !void {
        _ = bot;
        _ = self;
        _ = actions;
        std.sort.insertion(Point2, game_info.expansion_locations, game_info.start_location, closerToStart);
    }

    pub fn onStep(
        self: *Self,
        bot: Bot,
        game_info: GameInfo,
        actions: *Actions,
    ) !void {
        const own_units = bot.units.values();
        self.runBuild(bot, game_info, actions);
        rallyBuildings(bot, actions);
        doUpgrades(bot, actions);
        self.produceUnits(bot, game_info, actions);
        useChronoboost(bot, actions);
        handleIdleWorkers(own_units, bot.mineral_patches, game_info, actions);
        moveWorkersToGas(bot, actions);
        controlArmy(bot, game_info, actions);
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

    var my_bot = try ProtossBot.init(gpa);
    defer my_bot.deinit();

    try zig_sc2.run(&my_bot, 2, gpa, .{});
}
