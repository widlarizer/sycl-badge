const std = @import("std");
const builtin = @import("builtin");
const cart = @import("cart-api");
const allocator = std.heap.c_allocator;

const global = struct {
    pub var rand_seed: u8 = 0;
    pub var rand: std.rand.DefaultPrng = undefined;
};

fn rand_mod(comptime T: type, max: T) T {
    log("max: {}", .{max});
    return @intCast(@mod(@as(T, @as(T, @truncate(global.rand.next()))), @as(T, @intCast(max))));
}

export fn start() void {
    global.rand = std.rand.DefaultPrng.init(global.rand_seed);
    scene_intro();
}

var scene: enum { intro, game } = .intro;

export fn update() void {
    scene_game();
}

const lines = &[_][]const u8{
    "Press START",
};
const spacing = (cart.font_height * 4 / 3);

var ticks: u8 = 0;
var flash = false;
fn scene_intro() void {
    set_background();

    @memset(cart.neopixels, .{
        .r = 0,
        .g = 0,
        .b = 0,
    });

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
fn log(comptime fmt: []const u8, args: anytype) void {
    if (!builtin.target.isWasm()) return;
    var buf: [300]u8 = undefined;
    const str = std.fmt.bufPrint(&buf, fmt, args) catch @panic("codebug");
    cart.trace(str);
}

pub fn panic(
    msg: []const u8,
    trace: ?*std.builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    log("panic: {s}", .{msg});
    if (trace) |t| {
        cart.trace("dumping error trace...");
        _ = t;
        //std.debug.dumpStackTrace(t.*);
    } else {
        cart.trace("no error trace");
    }
    cart.trace("dumping current stack...");
    _ = ret_addr;
    //std.debug.dumpCurrentStackTrace(ret_addr);
    cart.trace("breakpoint");
    while (true) {
        @breakpoint();
    }
}

fn spawn(t: Thingy) void {
    // Spawn sparkles
    flash = true;
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
            sparkle.ticks_to_live = 6 + @as(i8, @intCast(rand_mod(u32, 12)));
        }
    }
}

fn end(t: *Thingy) void {
    t.live = false;
    if (t.is_rocket) {
        spawn(t.*);
    }
}

const margin = 5;

fn launch() void {
    for (&thingies) |*thingy| {
        if (!thingy.live) {
            thingy.live = true;
            thingy.is_rocket = true;
            thingy.color = .{ .r = @intCast(31 / 4 + rand_mod(u5, 3 * 31 / 4)), .g = @intCast(63 / 4 + rand_mod(u6, 3 * 63 / 4)), .b = @intCast(31 / 4 + rand_mod(u5, 3 * 31 / 4)) };
            thingy.x = margin + rand_mod(u8, cart.screen_width - margin);
            thingy.y = margin + @as(u8, @intCast(cart.screen_height / 2)) + rand_mod(u8, cart.screen_height / 2 - margin);
            thingy.v_x = @as(i7, @intCast(rand_mod(u8, 8))) - 4;
            thingy.v_y = -10 - @as(i7, @intCast(rand_mod(u8, 3)));
            thingy.ticks_to_live = @as(i8, @intCast(30 + rand_mod(u8, 20)));
            break;
        }
    }
}

fn scene_game() void {
    log("start", .{});
    flash = false;
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

    log("kill expired", .{});
    // Kill expired thingies
    for (&thingies) |*thingy| {
        if (thingy.live) {
            thingy.ticks_to_live = @max(thingy.ticks_to_live - 1, 0);
            if (thingy.ticks_to_live == 0) {
                end(thingy);
                continue;
            }
            if (!builtin.target.isWasm() or tick % 2 == 0) {
                log("speed", .{});
                const tmp_x = @as(i32, @intCast(thingy.x)) +| thingy.v_x;
                const tmp_y = @as(i32, @intCast(thingy.y)) +| thingy.v_y;
                log("g", .{});
                const g = 1;
                if (thingy.is_rocket) {
                    thingy.v_y += g;
                }
                if ((tmp_x < margin or tmp_x > cart.screen_width - margin or tmp_y < margin or tmp_y > cart.screen_height - margin)) {
                    end(thingy);
                    continue;
                }
                thingy.x = @intCast(tmp_x);
                thingy.y = @intCast(tmp_y);
            }
        }
    }

    log("draw", .{});
    for (thingies) |thingy| {
        if (thingy.live) {
            const size: u32 = if (thingy.is_rocket) 5 else 1;
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

    const improbability = 10;
    if (tick % improbability == rand_mod(u32, improbability)) {
        launch();
    }
    // if (!control_cooldown) {
    //     if (cart.controls.select) {
    //         launch();
    //     }
    //     if (cart.controls.left) {
    //         scene = switch (scene) {
    //             .intro => .game,
    //             .game => .intro,
    //         };
    //     }
    // }

    // control_cooldown = false;
    // if (cart.controls.left or cart.controls.right or cart.controls.up or cart.controls.down or cart.controls.select) control_cooldown = true;
    // const dark = 16;
    @memset(cart.neopixels, if (flash) .{
        .r = 1,
        .g = 2,
        .b = 1,
    } else .{
        .r = 0,
        .g = 0,
        .b = 0,
    });
    log("end", .{});
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
