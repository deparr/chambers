const std = @import("std");
const physics = @import("physics");
const Ball = physics.Ball;
const Surface = physics.Surface;
const Allocator = std.mem.Allocator;
const Pos2 = physics.Pos2;
const Vec2 = physics.Vec2;
const graphics = @import("graphics.zig");

const chamber_height = 0.7;
const State = struct {
    pool_balls: [15]PBall = [15]PBall{},
    ball_x_i: [16]u11 = undefined,
    ball_y_i: [16]u11 = undefined,
    cue: Ball,
    in_pocket: u15 = 0,
    clear_steps: u16 = 0,

    rng: ?std.rand.DefaultPrng = null,

    fn ensureRngInitialized(self: *State, num_balls: usize) void {
        if (self.rng != null) {
            return;
        }

        var seed: u64 = 0;
        for (balls[0..num_balls]) |ball| {
            seed +%= @intFromFloat(@abs(ball.pos.x * 1000));
            seed +%= @intFromFloat(@abs(ball.pos.y * 1000));
            seed +%= @intFromFloat(@abs(ball.velocity.x * 1000));
            seed +%= @intFromFloat(@abs(ball.velocity.y * 1000));
        }

        self.rng = std.rand.DefaultPrng.init(seed);
    }

    fn setCueIntState(self: *State) void {
        self.ball_x_i[self.ball_x_i.len - 1] = @intFromFloat(std.math.clamp(self.cue.pos.x, 0.0, 1.0) * std.math.maxInt(@TypeOf(self.ball_x_i[0])));
        self.ball_y_i[self.ball_y_i.len - 1] = @intFromFloat(std.math.clamp(self.cue.pos.y, 0.0, 1.0) / chamber_height * std.math.maxInt(@TypeOf(self.ball_y_i[0])));
    }

    fn resetFromIntState(self: *State) void {
        for (0..self.pool_balls.len) |i| {
            var ball = &self.pool_balls[i].ball;
            const x: f32 = @floatFromInt(self.ball_x_i[i]);
            const y: f32 = @floatFromInt(self.ball_y_i[i]);

            ball.pos.x = x / std.math.maxInt(@TypeOf(self.ball_x_i[0]));
            ball.pos.y = y * chamber_height / std.math.maxInt(@TypeOf(self.ball_y_i[0]));
        }

        const cue_idx = self.pool_balls.len;
        const x: f32 = @floatFromInt(self.ball_x_i[cue_idx]);
        const y: f32 = @floatFromInt(self.ball_y_i[cue_idx]);
        state.cue.pos.x = x / std.math.maxInt(@TypeOf(self.ball_x_i[0]));
        state.cue.pos.y = y * chamber_height / std.math.maxInt(@TypeOf(self.ball_y_i[0]));
    }

    fn isInPocket(self: *State, idx: u4) bool {
        const one: u15 = 1;
        return (self.in_pocket & (one << idx)) > 0;
    }

    fn setInPocket(self: *State, idx: u4, is_in: bool) void {
        const one: u15 = 1;
        if (is_in) {
            self.in_pocket |= one << idx;
        } else {
            self.in_pocket &= ~(one << idx);
        }
    }
};

var state: State = undefined;
var balls: []Ball = undefined;
var chamber_pixels: []u32 = undefined;
var save_data: [saveSize()]u8 = undefined;

const PBall = struct {
    ball: Ball,
    id: u4,

    fn setIntState(self: *PBall) void {
        state.ball_x_i[self.id] = @intFromFloat(std.math.clamp(self.ball.pos.x, 0.0, 1.0) * std.math.maxInt(@TypeOf(state.ball_x_i[0])));
        state.ball_y_i[self.id] = @intFromFloat(std.math.clamp(self.ball.pos.y, 0.0, 1.0) / chamber_height * std.math.maxInt(@TypeOf(state.ball_y_i[0])));
    }
};

const ball_colors = [_]u32{
    0xff000000,
    0xff10bcfb, // 1
    0xffff0000, // 2
    0xff0000ff, // 3
    0xffed0571, // 4
    0xff2275ec, // 5
    0xff0ca80e, // 6
    0xff0505a3, // 7
};
const off_white: u32 = 0xffd3e8e8;
const table_color: u32 = 0xff658a9c;
const pocket_color: u32 = 0xff1b1f2e;

const ball_radius = 0.03;
const pocket_radius = ball_radius * 2;
const pockets = [_]Pos2{
    .{ .x = 0.02, .y = 0.02 },
    .{ .x = 0.50, .y = 0.00 },
    .{ .x = 0.98, .y = 0.02 },
    .{ .x = 0.02, .y = chamber_height - 0.02 },
    .{ .x = 0.50, .y = chamber_height },
    .{ .x = 0.98, .y = chamber_height - 0.02 },
};

const head_ball_pos = Pos2{
    .x = 0.33,
    .y = 0.35,
};
const cue_home = head_ball_pos.add(.{ .x = 0.5, .y = 0.0 });

const walls = &[4]Surface{
    .{ .a = .{ .x = 0.00, .y = 0.01 }, .b = .{ .x = 0.99, .y = 0.01 } },
    .{ .a = .{ .x = 0.00, .y = 0.69 }, .b = .{ .x = 0.01, .y = 0.01 } },
    .{ .a = .{ .x = 0.99, .y = 0.69 }, .b = .{ .x = 0.01, .y = 0.69 } },
    .{ .a = .{ .x = 0.99, .y = 0.01 }, .b = .{ .x = 0.99, .y = 0.69 } },
};

extern fn logWasm(s: [*]u8, len: usize) void;
fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch unreachable;
    logWasm(s.ptr, s.len);
}

pub export fn init(max_balls: usize, max_chamber_pixels: usize) void {
    physics.assertBallLayout();
    balls = std.heap.wasm_allocator.alloc(Ball, max_balls) catch {
        return;
    };

    chamber_pixels = std.heap.wasm_allocator.alloc(u32, max_chamber_pixels) catch {
        return;
    };

    initPoolBalls();
    resetTable();
}

pub export fn saveMemory() [*]u8 {
    return &save_data;
}

pub export fn ballsMemory() [*]Ball {
    return balls.ptr;
}

pub export fn canvasMemory() [*]u32 {
    return chamber_pixels.ptr;
}

pub export fn saveSize() usize {
    var len: usize = getRequiredBytesPacked(@TypeOf(state.ball_x_i));
    len += getRequiredBytesPacked(@TypeOf(state.ball_y_i));
    len += @sizeOf(@TypeOf(state.clear_steps));
    len += @sizeOf(@TypeOf(state.in_pocket));
    return len;
}

fn getRequiredBytesPacked(comptime T: type) usize {
    const info = @typeInfo(T);
    const DataPacked = std.PackedIntSlice(info.Array.child);
    return DataPacked.bytesRequired(info.Array.len);
}

fn savePacked(start_idx: usize, data: anytype) usize {
    const DataPacked = std.PackedIntSlice(@TypeOf(data[0]));
    const len = DataPacked.bytesRequired(data.len);
    var data_packed = DataPacked.init(save_data[start_idx .. start_idx + len], data.len);
    for (0..data.len) |i| {
        data_packed.set(i, data[i]);
    }
    return start_idx + len;
}

fn loadPacked(start_idx: usize, data: anytype) usize {
    const DataPacked = std.PackedIntSlice(@TypeOf(data[0]));
    const len = DataPacked.bytesRequired(data.len);
    var data_packed = DataPacked.init(save_data[start_idx .. start_idx + len], data.len);
    for (0..data.len) |i| {
        data[i] = data_packed.get(i);
    }
    return start_idx + len;
}

pub export fn save() void {
    var idx: usize = 0;

    idx = savePacked(idx, state.ball_x_i);
    idx = savePacked(idx, state.ball_y_i);

    const clear_steps_out = std.mem.asBytes(&state.clear_steps);
    @memcpy(save_data[idx .. idx + clear_steps_out.len], clear_steps_out);
    idx += clear_steps_out.len;

    const in_pocket_out = std.mem.asBytes(&state.in_pocket);
    @memcpy(save_data[idx .. idx + in_pocket_out.len], in_pocket_out);
    idx += in_pocket_out.len;
}

pub export fn load() void {
    var idx: usize = 0;

    idx = loadPacked(idx, &state.ball_x_i);
    idx = loadPacked(idx, &state.ball_y_i);
    const clear_step_in = std.mem.asBytes(&state.clear_steps);
    @memcpy(clear_step_in, save_data[idx .. idx + clear_step_in.len]);
    idx += clear_step_in.len;

    const in_pocket_in = std.mem.asBytes(&state.in_pocket);
    @memcpy(in_pocket_in, save_data[idx .. idx + in_pocket_in.len]);
    idx += in_pocket_in.len;


    state.resetFromIntState();
}

//     0
//    1 2
//   3 4 5
//  6 7 8 9
// 0 1 2 3 4
fn resetTable() void {
    // const x_off = ball_radius + 0.005;
    // var pool_balls = state.pool_balls;
    // const off = 0.05105;

    const head_y = head_ball_pos.y;
    const r2 = 2 * ball_radius;
    const r3 = 3 * ball_radius;
    const r4 = 4 * ball_radius;
    // TODO figure out a way to do this programatically
    state.pool_balls[0].ball.pos = head_ball_pos;

    state.pool_balls[1].ball.pos.x = 0.27895;
    state.pool_balls[2].ball.pos.x = 0.27895;
    state.pool_balls[1].ball.pos.y = head_y + ball_radius;
    state.pool_balls[2].ball.pos.y = head_y - ball_radius;

    state.pool_balls[3].ball.pos.x = 0.2279;
    state.pool_balls[4].ball.pos.x = 0.2279;
    state.pool_balls[5].ball.pos.x = 0.2279;
    state.pool_balls[3].ball.pos.y = head_y + r2;
    state.pool_balls[4].ball.pos.y = head_y;
    state.pool_balls[5].ball.pos.y = head_y - r2;

    state.pool_balls[6].ball.pos.x = 0.17685;
    state.pool_balls[7].ball.pos.x = 0.17685;
    state.pool_balls[8].ball.pos.x = 0.17685;
    state.pool_balls[9].ball.pos.x = 0.17685;
    state.pool_balls[6].ball.pos.y = head_y + r3;
    state.pool_balls[7].ball.pos.y = head_y + ball_radius;
    state.pool_balls[8].ball.pos.y = head_y - ball_radius;
    state.pool_balls[9].ball.pos.y = head_y - r3;

    state.pool_balls[10].ball.pos.x = 0.1258;
    state.pool_balls[11].ball.pos.x = 0.1258;
    state.pool_balls[12].ball.pos.x = 0.1258;
    state.pool_balls[13].ball.pos.x = 0.1258;
    state.pool_balls[14].ball.pos.x = 0.1258;
    state.pool_balls[10].ball.pos.y = head_y + r4;
    state.pool_balls[11].ball.pos.y = head_y + r2;
    state.pool_balls[12].ball.pos.y = head_y;
    state.pool_balls[13].ball.pos.y = head_y - r2;
    state.pool_balls[14].ball.pos.y = head_y - r4;

    state.clear_steps = 0;
    state.in_pocket = 0;
    for (&state.pool_balls) |*ball| {
        ball.ball.velocity = Vec2.zero;
        ball.setIntState();
    }

    state.cue.pos = cue_home;
    state.cue.velocity = Vec2.zero;
    state.setCueIntState();
}

fn initPoolBalls() void {
    for (0..state.pool_balls.len) |i| {
        state.pool_balls[i] = .{
            .ball = .{
                .pos = .{ .x = 0.5, .y = 0.35 },
                .r = ball_radius,
                .velocity = .{ .x = 0.0, .y = 0.0 },
            },
            .id = @intCast(i),
        };
    }
    state.cue = .{ .velocity = Vec2.zero, .r = ball_radius, .pos = cue_home };
    state.in_pocket = 0;
}

fn clampSpeed(ball: *Ball) void {
    const max_speed = 6.0;
    const max_speed_2 = max_speed * max_speed;
    const ball_speed_2 = ball.velocity.length_2();
    if (ball_speed_2 > max_speed_2) {
        const ball_speed = std.math.sqrt(ball_speed_2);
        ball.velocity = ball.velocity.mul(max_speed / ball_speed);
    }
}

// has elasticity of 1.0
fn pballCollision(a: *Ball, b: *Ball) void {
    const n = b.pos.sub(a.pos).normalized();
    const vel_diff = a.velocity.sub(b.velocity);
    const change_in_velocity = n.mul(vel_diff.dot(n));

    a.velocity = a.velocity.sub(change_in_velocity);
    // NOTE: This only works because a and b have the same mass
    b.velocity = b.velocity.add(change_in_velocity);

    const balls_distance = a.pos.sub(b.pos).length();
    const overlap = a.r + b.r - balls_distance;
    if (overlap > 0) {
        b.pos = b.pos.add(n.mul(overlap / 2.0));
        a.pos = a.pos.add(n.mul(-overlap / 2.0));
    }
}

fn checkWallCollisions(ball: *Ball, delta: f32) void {
    for (walls) |*wall| {
        var obj_normal = wall.normal();
        const ball_collision_point_offs = obj_normal.mul(-ball.r);
        const ball_collision_point = ball.pos.add(ball_collision_point_offs);

        const resolution = wall.collisionResolution(ball_collision_point, ball.velocity.mul(delta));
        if (resolution) |r| {
            physics.applyCollision(ball, r, obj_normal, Vec2.zero, delta, 1.0);
            return;
        }
    }
}

pub export fn step(num_balls: usize, delta: f32) void {
    state.ensureRngInitialized(num_balls);
    const min_sim_ball_v = 0.7;
    const min_sim_ball_v_2 = min_sim_ball_v * min_sim_ball_v;
    const pball_v_thres = 0.004;
    const pball_friction = 0.97;
    const random = state.rng.?.random();

    var cue = &state.cue;
    for (0..num_balls) |i| {
        var ball = &balls[i];
        if (ball.velocity.length_2() < min_sim_ball_v_2) {
            ball.velocity.x = random.float(f32) - 0.5;
            ball.velocity.y = random.float(f32) - 0.5;
            ball.velocity = ball.velocity.normalized().mul(min_sim_ball_v);
        }

        const center_dist = ball.pos.sub(cue.pos).length();
        if (center_dist < ball.r + cue.r) {
            physics.applyBallCollision(ball, cue);
        }
    }

    cue.pos = cue.pos.add(cue.velocity.mul(delta));
    if (cue.pos.x > 0.99 or cue.pos.x < 0.00 or cue.pos.y > 0.69 or cue.pos.y < 0.00) {
        print("reset from a oob pos {any}", .{cue.pos});
        cue.pos = cue_home;
        // cue.velocity = Vec2.zero;
    }
    checkWallCollisions(cue, delta);

    if (state.in_pocket == std.math.maxInt(@TypeOf(state.in_pocket))) {
        if (state.clear_steps < 2000) {
            state.clear_steps += 1;
            state.setCueIntState();
            return;
        }
        resetTable();
    }

    pballs: for (&state.pool_balls, 0..) |*pball, i| {
        if (state.isInPocket(pball.id)) continue;
        var pball_ball = &pball.ball;
        for (pockets) |pocket| {
            if (pball_ball.pos.sub(pocket).length() < pocket_radius) {
                state.setInPocket(pball.id, true);
                pball.ball.velocity = Vec2.zero;
                pball.ball.pos = .{ .x = 1.5, .y = 1.0 };
                pball.setIntState();
                continue :pballs;
            }
        }

        checkWallCollisions(pball_ball, delta);

        const cue_dist = cue.pos.sub(pball_ball.pos).length();
        if (cue_dist < pball_ball.r + cue.r) {
            pballCollision(pball_ball, cue);
        }

        for (i + 1..state.pool_balls.len) |j| {
            if (j == i) continue;
            const oball = &state.pool_balls[j];
            const oball_ball = &oball.ball;
            if (state.isInPocket(oball.id)) continue;

            const center_dist = oball_ball.pos.sub(pball_ball.pos).length();
            if (center_dist < pball_ball.r + oball_ball.r) {
                pballCollision(pball_ball, oball_ball);
                break;
            }
        }

        if (pball_ball.velocity.length() < pball_v_thres) {
            pball_ball.velocity = Vec2.zero;
        }
        pball_ball.pos = pball_ball.pos.add(pball_ball.velocity.mul(delta).mul(pball_friction));
        pball.setIntState();
    }

    clampSpeed(cue);
    state.setCueIntState();
}

pub export fn render(canvas_width: usize, canvas_height: usize) void {
    const this_frame_data = chamber_pixels[0 .. canvas_width * canvas_height];
    @memset(this_frame_data, table_color);

    const graphics_canvas: graphics.Canvas = .{
        .data = this_frame_data,
        .width = canvas_width,
    };

    for (pockets) |pocket| {
        graphics.renderCircle(pocket, pocket_radius, &graphics_canvas, pocket_color);
    }

    for (state.pool_balls, 1..) |ball, i| {
        if (state.isInPocket(ball.id)) {
            continue;
        }
        graphics.renderCircle(ball.ball.pos, ball.ball.r, &graphics_canvas, ball_colors[i % 8]);
        if (i > 8) {
            graphics.renderCircle(ball.ball.pos, ball.ball.r / 3.0, &graphics_canvas, off_white);
        }
    }

    graphics.renderCircle(state.cue.pos, ball_radius, &graphics_canvas, off_white);
}
