const std = @import("std");
const physics = @import("physics.zig");
const Ball = physics.Ball;
const Surface = physics.Surface;
const Allocator = std.mem.Allocator;

const State = struct {};

var balls: []Ball = undefined;
var chamber_pixels: []u32 = undefined;

const left_plat = Surface{
    .a = .{
        .x = 0.1,
        .y = 0.5,
    },
    .b = .{
        .x = 0.4,
        .y = 0.2,
    },
};

const right_plat = Surface{
    .a = .{
        .x = 0.6,
        .y = left_plat.b.y,
    },
    .b = .{
        .x = 0.9,
        .y = left_plat.a.y,
    },
};

pub export fn init(max_balls: usize, max_chamber_pixels: usize) void {
    physics.assertBallLayout();
    balls = std.heap.wasm_allocator.alloc(Ball, max_balls) catch {
        return;
    };

    chamber_pixels = std.heap.wasm_allocator.alloc(u32, max_chamber_pixels) catch {
        return;
    };
}

pub export fn saveMemory() ?*void {
    return null;
}

pub export fn ballsMemory() ?*void {
    return @ptrCast(balls.ptr);
}

pub export fn canvasMemory() ?*void {
    return @ptrCast(chamber_pixels.ptr);
}

pub export fn saveSize() usize {
    return 0;
}

pub export fn save() void {}

pub export fn load() void {}

pub export fn step(num_balls: usize, delta: f32) void {
    balls: for (0..num_balls) |i| {
        const ball = &balls[i];
        physics.applyGravity(ball, delta);

        const obj_normal = left_plat.normal();
        const ball_collision_point_offs = obj_normal.mul(-ball.r);
        const ball_collision_point = ball.pos.add(ball_collision_point_offs);

        const resolution = left_plat.collisionResolution(ball_collision_point, ball.velocity.mul(delta));
        if (resolution) |r| {
            physics.applyCollision(ball, r, obj_normal, physics.Vec2.zero, delta, 0.9);
            continue :balls;
        }

        const obj_normal_2 = right_plat.normal();
        const ball_collision_point_offs_2 = obj_normal_2.mul(-ball.r);
        const ball_collision_point_2 = ball.pos.add(ball_collision_point_offs_2);

        const resolution_2 = right_plat.collisionResolution(ball_collision_point_2, ball.velocity);
        if (resolution_2) |r| {
            physics.applyCollision(ball, r, obj_normal_2, physics.Vec2.zero, delta, 0.9);
        }
    }
}

fn renderPlatform(canvas_width: usize, canvas_height: usize, plat: Surface) void {
    const canvas_width_f: f32 = @floatFromInt(canvas_width);
    const canvas_height_f: f32 = @floatFromInt(canvas_height);
    const x_start_px: usize = @intFromFloat(plat.a.x * canvas_width_f);
    const x_end_px: usize = @intFromFloat(plat.b.x * canvas_width_f);
    const x_dist_px: f32 = (plat.b.x - plat.a.x) * canvas_width_f;

    const y_start_px = canvas_height_f - plat.a.y * canvas_width_f;
    const y_end_px = canvas_height_f - plat.b.y * canvas_width_f;
    const y_dist_px: f32 = y_end_px - y_start_px;

    for (x_start_px..x_end_px) |x| {
        const interp: f32 = @as(f32, @floatFromInt(x - x_start_px)) / x_dist_px;
        const y_f = y_start_px + y_dist_px * interp;
        const y: usize = @intFromFloat(y_f);

        for (y -| 2..y + 2) |i| {
            chamber_pixels[i * canvas_width + x] = 0xff000000;
        }
    }

}

pub export fn render(canvas_width: usize, canvas_height: usize) void {
    @memset(chamber_pixels, 0xffffffff);

    renderPlatform(canvas_width, canvas_height, left_plat);
    renderPlatform(canvas_width, canvas_height, right_plat);
}
