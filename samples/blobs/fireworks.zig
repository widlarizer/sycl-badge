const std = @import("std");
const cart = @import("cart-api");
const allocator = std.heap.c_allocator;

const global = struct {
    pub var rand_seed: u8 = 0;
    pub var rand: std.rand.DefaultPrng = undefined;
};

fn rand_mod(comptime T: type, max: T) T {
    return @intCast(@mod(@as(T, @intCast(global.rand.next())), @as(T, @intCast(max))));
}

export fn start() void {
    global.rand = std.rand.DefaultPrng.init(global.rand_seed);
}

var scene: enum { intro, game } = .intro;

export fn update() void {
    switch (scene) {
        .intro => scene_intro(),
        .game => scene_game(),
    }
}

const lines = &[_][]const u8{
    "Press START",
};
const spacing = (cart.font_height * 4 / 3);

var ticks: u8 = 0;

fn scene_intro() void {
    set_background();

    @memset(cart.neopixels, .{
        .r = 0,
        .g = 0,
        .b = 0,
    });

    if (ticks / 128 == 0) {
        // Make the neopixel 24-bit color LEDs a nice Zig orange
        @memset(cart.neopixels, .{
            .r = 247,
            .g = 164,
            .b = 29,
        });
    }

    const y_start = (cart.screen_height - (cart.font_height + spacing * (lines.len - 1))) / 2;

    // Write it out!
    for (lines, 0..) |line, i| {
        cart.text(.{
            .text_color = .{ .r = 31, .g = 63, .b = 31 },
            .str = line,
            .x = @intCast((cart.screen_width - cart.font_width * line.len) / 2),
            .y = @intCast(y_start + spacing * i),
        });
    }

    if (ticks == 0) cart.red_led.* = !cart.red_led.*;
    if (cart.controls.start) scene = .game;

    ticks +%= 4;
}

const Player = enum(u8) { x = 0, o = 1, none = std.math.maxInt(u8) };

// var selected_x: u8 = 0;
// var selected_y: u8 = 0;
const Thingy = struct {
    live: bool = false,
    is_rocket: bool = false,
    color: cart.DisplayColor = .{ .r = 0, .g = 0, .b = 0 },
    x: u8 = 0,
    y: u8 = 0,
    v_x: i7 = 0,
    v_y: i7 = 0,
    ticks_to_live: i8 = 0,
};

var thingies: [100]Thingy = [_]Thingy{.{}} ** 100;

var control_cooldown: bool = false;
var tick: u32 = 0;

fn spawn(t: Thingy) void {
    // Spawn sparkles
    var phi: f32 = 0.0;
    var sparkles_done: u32 = 0;
    const num_sparkles = 10 + rand_mod(u32, 6);

    for (&thingies) |*sparkle| {
        if (sparkles_done == num_sparkles) {
            break;
        }
        if (!sparkle.live) {
            phi += 2 * std.math.pi / @as(f32, @floatFromInt(num_sparkles));
            phi += @as(f32, @floatFromInt(rand_mod(u32, 100))) / 300;
            sparkles_done += 1;
            sparkle.live = true;
            sparkle.is_rocket = false;
            sparkle.color = t.color;
            sparkle.x = t.x;
            sparkle.y = t.y;
            sparkle.v_x = @intFromFloat(5 * @sin(phi));
            sparkle.v_y = @intFromFloat(5 * @cos(phi));
            sparkle.ticks_to_live = 12 + rand_mod(i8, 12);
        }
    }
}

fn end(t: *Thingy) void {
    t.live = false;
    if (t.is_rocket) {
        spawn(t.*);
    }
}

fn launch() void {
    for (&thingies) |*thingy| {
        if (!thingy.live) {
            thingy.live = true;
            thingy.is_rocket = true;
            thingy.color = .{ .r = @intCast(31 / 4 + rand_mod(u5, 3 * 31 / 4)), .g = @intCast(63 / 4 + rand_mod(u6, 3 * 63 / 4)), .b = @intCast(31 / 4 + rand_mod(u5, 3 * 31 / 4)) };
            thingy.x = rand_mod(u8, cart.screen_width);
            thingy.y = @as(u8, @intCast(cart.screen_height / 2)) + rand_mod(u8, cart.screen_height / 2);
            thingy.v_x = @intCast(rand_mod(u8, 8) - 4);
            thingy.v_y = @intCast(-10 - @as(i7, @intCast(rand_mod(u8, 3))));
            thingy.ticks_to_live = 15 + rand_mod(i8, 20);
            break;
        }
    }
}

fn scene_game() void {
    tick += 1;
    set_background();

    const title = "EMIL";
    const subtitle = "(widlarizer)";
    cart.text(.{
        .text_color = .{ .r = 31, .g = 63, .b = 31 },
        .str = title,
        .x = @intCast((cart.screen_width - cart.font_width * title.len) / 2),
        .y = 20,
    });
    cart.text(.{
        .text_color = .{ .r = 31, .g = 63, .b = 31 },
        .str = subtitle,
        .x = @intCast((cart.screen_width - cart.font_width * subtitle.len) / 2),
        .y = 40,
    });

    // Kill expired thingies
    for (&thingies) |*thingy| {
        if (thingy.live) {
            thingy.ticks_to_live = @max(thingy.ticks_to_live - 1, 0);
            if (thingy.ticks_to_live == 0) {
                end(thingy);
                continue;
            }
            const margin = 10;
            if (tick % 2 == 0) {
                thingy.x = @intCast(@as(i16, @intCast(thingy.x)) + thingy.v_x);
                thingy.y = @intCast(@as(i16, @intCast(thingy.y)) + thingy.v_y);
                if (thingy.is_rocket and (thingy.x < margin or thingy.x > cart.screen_width - margin or thingy.y < margin or thingy.y > cart.screen_height - margin)) {
                    end(thingy);
                }
                const g = 1;
                if (thingy.is_rocket) {
                    thingy.v_y += g;
                }
            }
        }
    }

    for (thingies) |thingy| {
        if (thingy.live) {
            const size: u32 = if (thingy.is_rocket) 2 else 1;
            cart.rect(.{
                .stroke_color = thingy.color,
                // .fill_color = color,
                .x = thingy.x,
                .y = thingy.y,
                .width = size,
                .height = size,
            });
        }
    }

    const improbability = 30;
    if (tick % improbability == rand_mod(u32, improbability)) {
        launch();
    }
    if (!control_cooldown) {
        if (cart.controls.select) {
            launch();
        }
        if (cart.controls.left) {
            scene = switch (scene) {
                .intro => .game,
                .game => .intro,
            };
        }
    }

    control_cooldown = false;
    if (cart.controls.left or cart.controls.right or cart.controls.up or cart.controls.down or cart.controls.select) control_cooldown = true;
}

fn set_background() void {
    const ratio = 0;
    // const ratio = (4095 - @as(f32, @floatFromInt(cart.light_level.*))) / 4095 * 0.2;

    @memset(cart.framebuffer, cart.DisplayColor{
        .r = @intFromFloat(ratio * 31),
        .g = @intFromFloat(ratio * 63),
        .b = @intFromFloat(ratio * 31),
    });
}
