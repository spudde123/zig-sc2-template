const std = @import("std");
const mem = std.mem;
const log = std.log;

const zig_sc2 = @import("zig-sc2");
const BotContext = zig_sc2.BotContext;
const bot_data = zig_sc2.bot_data;
const Actions = bot_data.Actions;
const Bot = bot_data.Bot;
const GameInfo = bot_data.GameInfo;
const Point2 = bot_data.Point2;
const Unit = bot_data.Unit;
const UnitId = bot_data.UnitId;
const unit_group = bot_data.unit_group;
const grid_utils = bot_data.grid_utils;

const TransportState = enum {
    waiting_for_medivac,
    loading,
    unloading,
    finished,
};

const MedivacBot = struct {
    allocator: mem.Allocator,
    name: []const u8,
    race: bot_data.Race,

    build_step: u8 = 0,
    transport_state: TransportState = .waiting_for_medivac,
    medivac_tag: u64 = 0,
    load_tags: [3]u64 = .{ 0, 0, 0 },
    load_tag_count: usize = 0,

    pub fn init(base_allocator: mem.Allocator) !MedivacBot {
        return .{
            .allocator = base_allocator,
            .name = "MedivacExample",
            .race = .terran,
        };
    }

    pub fn deinit(self: *MedivacBot) void {
        _ = self;
    }

    pub fn onStart(self: *MedivacBot, ctx: BotContext) !void {
        _ = self;
        ctx.actions.tagGame("medivac_example");
    }

    fn countReady(units: []Unit, unit_id: UnitId) usize {
        var count: usize = 0;
        for (units) |unit| {
            if (unit.unit_type == unit_id and unit.isReady()) count += 1;
        }
        return count;
    }

    fn findFreeGeyser(near: Point2, units: []Unit, geysers: []Unit) ?Unit {
        var closest: ?Unit = null;
        var min_dist = std.math.floatMax(f32);

        geyser_loop: for (geysers) |geyser| {
            for (units) |unit| {
                if (unit.unit_type != .Refinery) continue;
                if (unit.position.distanceSquaredTo(geyser.position) < 1) continue :geyser_loop;
            }

            const dist = near.distanceSquaredTo(geyser.position);
            if (dist < min_dist) {
                closest = geyser;
                min_dist = dist;
            }
        }

        return closest;
    }

    fn runBuild(self: *MedivacBot, bot: *const Bot, game_info: *const GameInfo, actions: *Actions) void {
        const own_units = bot.units.values();
        const ramp = game_info.getMainBaseRamp();

        switch (self.build_step) {
            0 => {
                if (countReady(own_units, .SupplyDepot) + bot.unitsPending(.SupplyDepot) >= 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.food_used >= 14 and bot.minerals >= 100) {
                    var workers = unit_group.includeType(.SCV, own_units);
                    if (workers.findClosest(ramp.depot_first.?)) |worker| {
                        actions.build(worker.unit.tag, .SupplyDepot, ramp.depot_first.?, false);
                    }
                }
            },
            1 => {
                if (countReady(own_units, .Barracks) + bot.unitsPending(.Barracks) >= 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 150 and countReady(own_units, .SupplyDepot) >= 1) {
                    var workers = unit_group.includeType(.SCV, own_units);
                    if (workers.findClosest(ramp.barracks_with_addon.?)) |worker| {
                        actions.build(worker.unit.tag, .Barracks, ramp.barracks_with_addon.?, false);
                    }
                }
            },
            2 => {
                if (countReady(own_units, .Refinery) + bot.unitsPending(.Refinery) >= 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 75) {
                    var command_centers = unit_group.includeType(.CommandCenter, own_units);
                    if (command_centers.next()) |command_center| {
                        const geyser = unit_group.findClosestUnit(bot.vespene_geysers, command_center.position) orelse return;
                        var workers = unit_group.includeType(.SCV, own_units);
                        if (workers.findClosest(geyser.unit.position)) |worker| {
                            actions.buildOnUnit(worker.unit.tag, .Refinery, geyser.unit.tag, false);
                        }
                    }
                }
            },
            3 => {
                if (countReady(own_units, .Refinery) + bot.unitsPending(.Refinery) >= 2) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 75) {
                    var command_centers = unit_group.includeType(.CommandCenter, own_units);
                    if (command_centers.next()) |command_center| {
                        const geyser = findFreeGeyser(command_center.position, own_units, bot.vespene_geysers) orelse return;
                        var workers = unit_group.includeType(.SCV, own_units);
                        if (workers.findClosestUsingAbility(geyser.position, .Harvest_Gather_SCV)) |worker| {
                            actions.buildOnUnit(worker.unit.tag, .Refinery, geyser.tag, false);
                        }
                    }
                }
            },
            4 => {
                if (countReady(own_units, .Factory) + bot.unitsPending(.Factory) >= 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 150 and bot.vespene >= 100) {
                    const near = ramp.top_center.towards(game_info.start_location, 8);
                    if (grid_utils.findPlacement(game_info.placement_grid, .FactoryTechLab, near, 20)) |location| {
                        var workers = unit_group.includeType(.SCV, own_units);
                        if (workers.findClosestUsingAbility(location, .Harvest_Gather_SCV)) |worker| {
                            actions.build(worker.unit.tag, .Factory, location, false);
                        }
                    }
                }
            },
            5 => {
                const depot_count = countReady(own_units, .SupplyDepot) + countReady(own_units, .SupplyDepotLowered) + bot.unitsPending(.SupplyDepot);
                if (depot_count >= 2) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 100) {
                    var workers = unit_group.includeType(.SCV, own_units);
                    if (workers.findClosestUsingAbility(ramp.depot_second.?, .Harvest_Gather_SCV)) |worker| {
                        actions.build(worker.unit.tag, .SupplyDepot, ramp.depot_second.?, false);
                    }
                }
            },
            6 => {
                if (countReady(own_units, .Starport) + bot.unitsPending(.Starport) >= 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 150 and bot.vespene >= 100) {
                    const near = ramp.top_center.towards(ramp.bottom_center, -15);
                    if (grid_utils.findPlacement(game_info.placement_grid, .Starport, near, 20)) |location| {
                        var workers = unit_group.includeType(.SCV, own_units);
                        if (workers.findClosestUsingAbility(location, .Harvest_Gather_SCV)) |worker| {
                            actions.build(worker.unit.tag, .Starport, location, false);
                        }
                    }
                }
            },
            7 => {
                if (countReady(own_units, .FactoryTechLab) + bot.unitsPending(.FactoryTechLab) >= 1) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 50 and bot.vespene >= 25) {
                    for (own_units) |unit| {
                        if (unit.unit_type != .Factory or !unit.isReady() or unit.addon_tag != 0 or unit.orders.len > 0) continue;
                        actions.useAbility(unit.tag, .Build_TechLab_Factory, false);
                    }
                }
            },
            8 => {
                const depot_count = countReady(own_units, .SupplyDepot) + countReady(own_units, .SupplyDepotLowered) + bot.unitsPending(.SupplyDepot);
                if (depot_count >= 3) {
                    self.build_step += 1;
                    return;
                }

                if (bot.minerals >= 100) {
                    const near = game_info.start_location.towards(ramp.top_center, 5);
                    if (grid_utils.findPlacement(game_info.placement_grid, .SupplyDepot, near, 20)) |location| {
                        var workers = unit_group.includeType(.SCV, own_units);
                        if (workers.findClosestUsingAbility(location, .Harvest_Gather_SCV)) |worker| {
                            actions.build(worker.unit.tag, .SupplyDepot, location, false);
                        }
                    }
                }
            },
            else => {},
        }
    }

    fn countUnits(bot: *const Bot, unit_id: UnitId) usize {
        var count = bot.unitsPending(unit_id);
        for (bot.units.values()) |unit| {
            if (unit.unit_type == unit_id) count += 1;
        }
        return count;
    }

    fn factoryHasReadyTechLab(bot: *const Bot, factory: Unit) bool {
        if (factory.addon_tag == 0) return false;
        const addon = bot.units.get(factory.addon_tag) orelse return false;
        return addon.unit_type == .FactoryTechLab and addon.isReady();
    }

    fn produceUnits(self: *const MedivacBot, bot: *const Bot, actions: *Actions) void {
        if (self.transport_state != .waiting_for_medivac) return;

        for (bot.units.values()) |structure| {
            if (!structure.isReady() or structure.orders.len > 0) continue;

            switch (structure.unit_type) {
                .Barracks => {
                    if (countUnits(bot, .Marine) < 2) actions.train(structure.tag, .Marine, false);
                },
                .Factory => {
                    if (factoryHasReadyTechLab(bot, structure) and countUnits(bot, .SiegeTank) < 1) {
                        actions.train(structure.tag, .SiegeTank, false);
                    }
                },
                .Starport => {
                    if (countUnits(bot, .Medivac) < 1) actions.train(structure.tag, .Medivac, false);
                },
                .CommandCenter, .OrbitalCommand, .PlanetaryFortress => {
                    const need_more = structure.ideal_harvesters - structure.assigned_harvesters >= 0;
                    if (need_more and bot.minerals >= 50) actions.train(structure.tag, .SCV, false);
                },
                else => {},
            }
        }
    }

    fn moveWorkersToGas(bot: *const Bot, actions: *Actions) void {
        const own_units = bot.units.values();
        for (own_units) |refinery| {
            if (refinery.unit_type != .Refinery or !refinery.isReady()) continue;

            const needed = refinery.ideal_harvesters - refinery.assigned_harvesters;
            var workers = unit_group.includeType(.SCV, own_units);

            if (needed > 0) {
                while (workers.next()) |worker| {
                    if (!worker.isUsingAbility(.Harvest_Gather_SCV)) continue;
                    const mineral = unit_group.findClosestUnit(bot.mineral_patches, worker.position) orelse return;
                    if (mineral.distance_squared < 2) {
                        actions.useAbilityOnUnit(worker.tag, .Smart, refinery.tag, false);
                        break;
                    }
                }
            } else if (needed < 0) {
                while (workers.next()) |worker| {
                    if (worker.orders.len == 0) continue;
                    if (worker.orders[0].ability_id != .Harvest_Gather_SCV) continue;
                    if (worker.orders[0].target != .tag or worker.orders[0].target.tag != refinery.tag) continue;
                    const mineral = unit_group.findClosestUnit(bot.mineral_patches, worker.position) orelse return;
                    actions.useAbilityOnUnit(worker.tag, .Smart, mineral.unit.tag, false);
                    break;
                }
            }
        }
    }

    fn handleIdleWorkers(bot: *const Bot, game_info: *const GameInfo, actions: *Actions) void {
        const mineral = unit_group.findClosestUnit(bot.mineral_patches, game_info.start_location) orelse return;
        for (bot.units.values()) |unit| {
            if (unit.unit_type == .SCV and unit.orders.len == 0) {
                actions.useAbilityOnUnit(unit.tag, .Smart, mineral.unit.tag, false);
            }
        }
    }

    fn isCargo(unit: Unit) bool {
        return unit.unit_type == .Marine or unit.unit_type == .SiegeTank;
    }

    fn readyCargoCount(units: []Unit) usize {
        var count: usize = 0;
        for (units) |unit| {
            if (isCargo(unit) and unit.isReady()) count += 1;
        }
        return count;
    }

    fn findMedivac(bot: *const Bot) ?Unit {
        for (bot.units.values()) |unit| {
            if (unit.unit_type == .Medivac and unit.isReady()) return unit;
        }
        return null;
    }

    fn logPassengers(medivac: Unit) void {
        log.info("Medivac {d} is carrying {d} passengers (cargo {d}/{d})", .{
            medivac.tag,
            medivac.passengers.len,
            medivac.cargo_space_taken,
            medivac.cargo_space_max,
        });
        for (medivac.passengers) |passenger| {
            log.info("  passenger tag={d} type={any} health={any}/{any} shield={any}/{any} energy={any}/{any}", .{
                passenger.tag,
                passenger.unit_type,
                passenger.health,
                passenger.health_max,
                passenger.shield,
                passenger.shield_max,
                passenger.energy,
                passenger.energy_max,
            });
        }
    }

    fn controlTransport(self: *MedivacBot, bot: *const Bot, actions: *Actions) void {
        switch (self.transport_state) {
            .waiting_for_medivac => {
                const medivac = findMedivac(bot) orelse return;
                self.medivac_tag = medivac.tag;

                const own_units = bot.units.values();
                if (readyCargoCount(own_units) < 2) return;

                self.load_tag_count = 0;
                for (own_units) |unit| {
                    if (!isCargo(unit) or !unit.isReady() or self.load_tag_count == self.load_tags.len) continue;
                    self.load_tags[self.load_tag_count] = unit.tag;
                    self.load_tag_count += 1;
                }

                // Smart is intentionally issued by each passenger, targeting
                // the medivac, rather than using Load_Medivac on the medivac.
                for (self.load_tags[0..self.load_tag_count]) |unit_tag| {
                    actions.useAbilityOnUnit(unit_tag, .Smart, medivac.tag, false);
                }
                self.transport_state = .loading;
            },
            .loading => {
                const medivac = bot.units.get(self.medivac_tag) orelse return;
                if (medivac.passengers.len == 0) return;

                logPassengers(medivac);
                // The unload target is the medivac itself, as required by the
                // UnloadAllAt_Medivac ability.
                actions.useAbilityOnUnit(medivac.tag, .UnloadAllAt_Medivac, medivac.tag, false);
                self.transport_state = .unloading;
            },
            .unloading => {
                const medivac = bot.units.get(self.medivac_tag) orelse return;
                if (medivac.passengers.len != 0) return;
                log.info("Medivac {d} finished unloading", .{medivac.tag});
                self.transport_state = .finished;
                actions.leaveGame();
            },
            .finished => {},
        }
    }

    pub fn onStep(self: *MedivacBot, ctx: BotContext) !void {
        self.runBuild(ctx.bot, ctx.game_info, ctx.actions);
        moveWorkersToGas(ctx.bot, ctx.actions);
        handleIdleWorkers(ctx.bot, ctx.game_info, ctx.actions);
        self.produceUnits(ctx.bot, ctx.actions);
        self.controlTransport(ctx.bot, ctx.actions);
    }

    pub fn onResult(self: *MedivacBot, ctx: BotContext, result: bot_data.Result) !void {
        _ = self;
        _ = ctx;
        _ = result;
    }
};

pub fn main(init: std.process.Init) !void {
    var bot = try MedivacBot.init(init.gpa);
    defer bot.deinit();

    _ = try zig_sc2.run(&bot, .{
        .step_count = 2,
        .gpa = init.gpa,
        .arena = init.arena,
        .env_map = init.environ_map,
        .args = init.minimal.args,
        .io = init.io,
    });
}
