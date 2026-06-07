const std = @import("std");
const mem = std.mem;

const zig_sc2 = @import("zig-sc2");
const BotContext = zig_sc2.BotContext;
const bot_data = zig_sc2.bot_data;
const unit_group = bot_data.unit_group;
const InfluenceMap = bot_data.InfluenceMap;
const Point2 = bot_data.Point2;

const TestBot = struct {
    const Self = @This();
    name: []const u8,
    race: bot_data.Race,
    allocator: mem.Allocator,
    locations_expanded_to: usize = 0,
    first_cc_tag: u64 = 0,
    pf_scv_tag: u64 = 0,

    pub fn onStart(
        self: *Self,
        ctx: BotContext,
    ) !void {
        const units = ctx.bot.units.values();
        self.first_cc_tag = cc_calc: {
            for (units) |unit| {
                if (unit.unit_type == .CommandCenter) break :cc_calc unit.tag;
            }
            unreachable;
        };

        self.pf_scv_tag = scv_calc: {
            for (units) |unit| {
                if (unit.unit_type == .SCV) break :scv_calc unit.tag;
            }
            unreachable;
        };
    }

    pub fn onStep(
        self: *Self,
        ctx: BotContext,
    ) !void {
        const units = ctx.bot.units.values();

        const maybe_first_cc = ctx.bot.units.get(self.first_cc_tag);
        if (maybe_first_cc == null) {
            ctx.actions.leaveGame();
            return;
        }
        const first_cc = maybe_first_cc.?;
        const main_base_ramp = ctx.game_info.getMainBaseRamp();

        var current_minerals = ctx.bot.minerals;
        if (ctx.bot.minerals > 50 and first_cc.isIdle()) {
            ctx.actions.train(self.first_cc_tag, .SCV, false);
            current_minerals -= 50;
        }

        if (current_minerals > 100 and unit_group.amountOfType(units, .SupplyDepot) == 0) {
            const closest_scv = findClosestCollectingUnit(units, first_cc.position);
            ctx.actions.build(
                closest_scv.tag,
                .SupplyDepot,
                main_base_ramp.depot_first.?,
                false,
            );
            current_minerals -= 100;
        }

        if (current_minerals > 100 and unit_group.amountOfType(units, .SupplyDepot) == 1) {
            const closest_scv = findClosestCollectingUnit(units, first_cc.position);
            ctx.actions.build(
                closest_scv.tag,
                .SupplyDepot,
                main_base_ramp.depot_second.?,
                false,
            );
            current_minerals -= 100;
        }

        if (current_minerals > 150 and unit_group.amountOfType(units, .SupplyDepot) == 2) {
            const closest_scv = findClosestCollectingUnit(units, first_cc.position);
            ctx.actions.build(
                closest_scv.tag,
                .Barracks,
                main_base_ramp.barracks_middle.?,
                false,
            );
            current_minerals -= 150;
        }

        if (current_minerals > 400) {
            const closest_scv = findClosestCollectingUnit(units, first_cc.position);
            ctx.actions.build(
                closest_scv.tag,
                .CommandCenter,
                ctx.game_info.expansion_locations[self.locations_expanded_to],
                false,
            );
            self.locations_expanded_to += 1;
            self.locations_expanded_to %= ctx.game_info.expansion_locations.len;
            current_minerals -= 400;
        }

        // For some reason I can't place the barracks in the middle
        // of the 2 depots if they are both down???
        // But works fine if they are up
        if (unit_group.amountOfType(units, .Barracks) > 0) {
            for (units) |unit| {
                if (unit.build_progress < 1 or unit.unit_type != .SupplyDepot) continue;
                ctx.actions.useAbility(unit.tag, .Morph_SupplyDepot_Lower, false);
            }
        }

        for (units) |unit| {
            if (unit.unit_type != .SCV or unit.orders.len > 0) continue;
            const closest_mineral_info = unit_group.findClosestUnit(ctx.bot.mineral_patches, first_cc.position).?;
            const closest_mineral_tag = closest_mineral_info.unit.tag;
            ctx.actions.useAbilityOnUnit(unit.tag, .Smart, closest_mineral_tag, false);
        }

        for (units) |unit| {
            if (unit.tag != self.pf_scv_tag) continue;

            const enemy_ramp = ctx.game_info.getEnemyMainBaseRamp();
            var map = InfluenceMap.fromGrid(self.allocator, ctx.game_info.pathing_grid, ctx.game_info.terrain_height) catch break;
            map.addInfluence(main_base_ramp.top_center.towards(ctx.game_info.start_location, 5), 10, 15, .none);
            defer map.deinit(self.allocator);

            const pf_res = try map.pathfindDirection(self.allocator, unit.position, enemy_ramp.top_center, .{});
            if (pf_res) |res| {
                ctx.actions.moveToPosition(unit.tag, res.next_point, false);
            }
            break;
        }

        drawRamps(ctx);
        debugTest(ctx);
        drawClimbablePoints(ctx);
        drawExpansionLocations(ctx);
    }

    fn drawExpansionLocations(
        ctx: BotContext,
    ) void {
        for (ctx.game_info.expansion_locations) |expansion| {
            const z = ctx.game_info.getTerrainZ(expansion);
            ctx.actions.debugTextWorld(
                "x",
                bot_data.Point3.fromPoint2(expansion, z + 0.5),
                .{ .r = 0, .g = 0, .b = 255 },
                32,
            );
        }
    }

    fn drawRamps(ctx: BotContext) void {
        for (ctx.game_info.ramps) |ramp| {
            for (ramp.points) |point| {
                const fx = @as(f32, @floatFromInt(point.x));
                const fy = @as(f32, @floatFromInt(point.y));
                const fz = ctx.game_info.getTerrainZ(.{ .x = fx, .y = fy });
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = fx + 0.5, .y = fy + 0.5, .z = fz },
                    .{ .r = 0, .g = 255, .b = 0 },
                    12,
                );
            }

            const z = ctx.game_info.getTerrainZ(ramp.top_center);

            if (ramp.depot_first) |depot_first| {
                const draw_loc = depot_first.add(.{ .x = 0.5, .y = 0.5 });
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = draw_loc.x - 1, .y = draw_loc.y - 1, .z = z },
                    .{ .r = 0, .g = 0, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = draw_loc.x - 1, .y = draw_loc.y, .z = z },
                    .{ .r = 0, .g = 0, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = draw_loc.x, .y = draw_loc.y - 1, .z = z },
                    .{ .r = 0, .g = 0, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = draw_loc.x, .y = draw_loc.y, .z = z },
                    .{ .r = 0, .g = 0, .b = 255 },
                    16,
                );
            }

            if (ramp.depot_second) |depot_second| {
                const draw_loc = depot_second.add(.{ .x = 0.5, .y = 0.5 });
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = draw_loc.x - 1, .y = draw_loc.y - 1, .z = z },
                    .{ .r = 0, .g = 0, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = draw_loc.x - 1, .y = draw_loc.y, .z = z },
                    .{ .r = 0, .g = 0, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = draw_loc.x, .y = draw_loc.y - 1, .z = z },
                    .{ .r = 0, .g = 0, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = draw_loc.x, .y = draw_loc.y, .z = z },
                    .{ .r = 0, .g = 0, .b = 255 },
                    16,
                );
            }

            if (ramp.barracks_middle) |rax_loc| {
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = rax_loc.x - 1, .y = rax_loc.y - 1, .z = z },
                    .{ .r = 0, .g = 255, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = rax_loc.x - 1, .y = rax_loc.y, .z = z },
                    .{ .r = 0, .g = 255, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = rax_loc.x - 1, .y = rax_loc.y + 1, .z = z },
                    .{ .r = 0, .g = 255, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = rax_loc.x, .y = rax_loc.y - 1, .z = z },
                    .{ .r = 0, .g = 255, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = rax_loc.x, .y = rax_loc.y, .z = z },
                    .{ .r = 0, .g = 255, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = rax_loc.x, .y = rax_loc.y + 1, .z = z },
                    .{ .r = 0, .g = 255, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = rax_loc.x + 1, .y = rax_loc.y - 1, .z = z },
                    .{ .r = 0, .g = 255, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = rax_loc.x + 1, .y = rax_loc.y, .z = z },
                    .{ .r = 0, .g = 255, .b = 255 },
                    16,
                );
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = rax_loc.x + 1, .y = rax_loc.y + 1, .z = z },
                    .{ .r = 0, .g = 255, .b = 255 },
                    16,
                );
            }
        }

        for (ctx.game_info.vision_blockers) |vb| {
            for (vb.points) |point| {
                const fx = @as(f32, @floatFromInt(point.x));
                const fy = @as(f32, @floatFromInt(point.y));
                const fz = ctx.game_info.getTerrainZ(.{ .x = fx, .y = fy });
                ctx.actions.debugTextWorld(
                    "o",
                    .{ .x = fx + 0.5, .y = fy + 0.5, .z = fz },
                    .{ .r = 255, .g = 0, .b = 0 },
                    12,
                );
            }
        }
    }

    fn debugTest(ctx: BotContext) void {
        const main_base_ramp = ctx.game_info.getMainBaseRamp();
        const z = ctx.game_info.getTerrainZ(main_base_ramp.top_center);
        const line_start = main_base_ramp.top_center.towards(main_base_ramp.bottom_center, -10);
        const line_end = ctx.game_info.start_location;
        ctx.actions.debugLine(
            bot_data.Point3.fromPoint2(line_start, z + 5),
            bot_data.Point3.fromPoint2(line_end, z + 5),
            .{ .r = 255, .g = 0, .b = 0 },
        );

        const box_start = line_start.add(.{ .x = 5, .y = 5 });
        const box_end = box_start.add(.{ .x = 10, .y = 10 });
        ctx.actions.debugBox(
            bot_data.Point3.fromPoint2(box_start, z + 2),
            bot_data.Point3.fromPoint2(box_end, z + 12),
            .{ .r = 0, .g = 255, .b = 0 },
        );

        const sphere_pos = box_end.add(.{ .x = 5, .y = 5 });
        ctx.actions.debugSphere(
            bot_data.Point3.fromPoint2(sphere_pos, z + 5),
            4,
            .{ .r = 0, .g = 0, .b = 255 },
        );
    }

    fn drawClimbablePoints(ctx: BotContext) void {
        for (ctx.game_info.climbable_points) |index| {
            const point = ctx.game_info.pathing_grid.indexToPoint(index).add(.{ .x = 0.5, .y = 0.5 });
            const z = ctx.game_info.getTerrainZ(point);
            ctx.actions.debugTextWorld(
                "x",
                bot_data.Point3.fromPoint2(point, z),
                .{ .r = 0, .g = 255, .b = 0 },
                24,
            );
        }
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

    fn findClosestCollectingUnit(units: []bot_data.Unit, pos: Point2) bot_data.Unit {
        var min_distance: f32 = std.math.floatMax(f32);
        var closest_unit: bot_data.Unit = undefined;
        for (units) |unit| {
            if (!unit.isCollecting()) continue;
            const dist_sqrd = unit.position.distanceSquaredTo(pos);
            if (dist_sqrd < min_distance) {
                min_distance = dist_sqrd;
                closest_unit = unit;
            }
        }
        return closest_unit;
    }
};

pub fn main(init: std.process.Init) !void {
    var my_bot = TestBot{ .name = "zig-bot", .race = .terran, .allocator = init.gpa };

    _ = try zig_sc2.run(&my_bot, .{
        .step_count = 2,
        .gpa = init.gpa,
        .arena = init.arena,
        .env_map = init.environ_map,
        .args = init.minimal.args,
        .io = init.io,
    });
}
