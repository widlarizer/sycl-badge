const std = @import("std");
const builtin = @import("builtin");
const cart = @import("cart-api");
const segments = @import("segments.zig");
const allocator = std.heap.c_allocator;

const global = struct {
    pub var rand_seed: u8 = 0;
    pub var rand: std.rand.DefaultPrng = undefined;
};

fn rand(comptime T: type) T {
    return @as(T, @truncate(global.rand.next()));
}

fn rand_mod(comptime T: type, max: T) T {
    return @intCast(@mod(@as(T, @as(T, @truncate(global.rand.next()))), @as(T, @intCast(max))));
}

export fn start() void {
    global.rand = std.rand.DefaultPrng.init(global.rand_seed);
    scene_intro();
}

var style: enum { normal, paint } = .paint;
var prev_start: bool = false;

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
            sparkle.ticks_to_live = 32 + @as(i8, @intCast(rand_mod(u32, 12)));
        }
    }
}

fn end(t: *Thingy) void {
    t.live = false;
    if (t.is_rocket) {
        spawn(t.*);
    }
}

const margin = 0;

fn launch() void {
    for (&thingies) |*thingy| {
        if (!thingy.live) {
            thingy.live = true;
            thingy.is_rocket = true;
            const r: u8 = rand(u8);
            // log("r {}", .{r});
            const g: u8 = rand_mod(u8, @intCast(@min(255, 512 - @as(u32, r))));
            // log("g {}", .{g});
            const b: u8 = @intCast(@min(255, 512 - @as(u32, r) - @as(u32, g)));
            // log("b {}", .{b});
            thingy.color = .{ .r = @intCast(r >> 3), .g = @intCast(g >> 2), .b = @intCast(b >> 3) };
            thingy.x = margin + rand_mod(u8, cart.screen_width - margin);
            thingy.y = margin + @as(u8, @intCast(cart.screen_height / 2)) + rand_mod(u8, cart.screen_height / 2 - margin);
            thingy.v_x = @as(i7, @intCast(rand_mod(u8, 8))) - 4;
            thingy.v_y = -10 - @as(i7, @intCast(rand_mod(u8, 3)));
            thingy.ticks_to_live = @as(i8, @intCast(10 + rand_mod(u8, 20)));
            break;
        }
    }
}

fn scene_game() void {
    flash = false;
    tick += 1;
    set_background();

    // Kill expired thingies
    for (&thingies) |*thingy| {
        if (thingy.live) {
            thingy.ticks_to_live = @max(thingy.ticks_to_live - 1, 0);
            if (thingy.ticks_to_live == 0) {
                end(thingy);
                continue;
            }
            if (!builtin.target.isWasm() or tick % 2 == 0) {
                const tmp_x = @as(i32, @intCast(thingy.x)) +| thingy.v_x;
                const tmp_y = @as(i32, @intCast(thingy.y)) +| thingy.v_y;
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

    for (thingies) |thingy| {
        if (thingy.live) {
            const size: u32 = if (thingy.is_rocket) 5 else 3;
            cart.rect(.{
                .fill_color = thingy.color,
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
    @memset(cart.neopixels, if (flash) .{
        .r = 0,
        .g = 0,
        .b = 1,
    } else .{
        .r = 0,
        .g = 0,
        .b = 0,
    });
    if (!prev_start and cart.controls.start) style = switch (style) {
        .normal => .paint,
        .paint => .normal,
    };

    prev_start = cart.controls.start;
}

fn noodle(x: u32, y: u32, len: u32, state: bool) void {
    if (y < 13) log("y = {}, x = {}, len = {}, state = {}", .{ y, x, len, state });
    const color: cart.DisplayColor = if (state) .{ .r = 0, .g = 0, .b = 0 } else .{ .r = 0, .g = 10, .b = 0 };
    if (!state) cart.hline(.{
        .x = @intCast(x),
        .y = @intCast(cart.screen_height - y),
        .len = len,
        .color = color,
    });
    // cart.rect(.{
    //     .stroke_color = color,
    //     .x = @intCast(x),
    //     .y = @intCast(cart.screen_height - y),
    //     .width = len -| 1,
    //     .height = 0,
    // });
}

fn set_background() void {
    switch (style) {
        .normal => {
            const foo = @embedFile("foo.bmp");
            var idx: u32 = 0x36; // bmp header
            for (0..cart.screen_height) |y| {
                for (0..cart.screen_width) |x| {
                    cart.rect(.{
                        .fill_color = if (foo[idx] == 0) .{ .r = 10, .g = 20, .b = 30 } else .{ .r = 0, .g = 0, .b = 0 },
                        .x = @intCast(x),
                        .y = @intCast(cart.screen_height - y),
                        .width = 2,
                        .height = 2,
                    });
                    idx += 3;
                }
            }
        },
        .paint => {
            // for (segments.segments) |segment| {
            //     if (cart.controls.start)
            //         cart.rect(.{
            //             .fill_color = .{ .r = 0, .g = 0, .b = 0 },
            //             .x = 0,
            //             .y = 0,
            //             .width = cart.screen_width,
            //             .height = cart.screen_height,
            //         });
            //     cart.rect(.{
            //         .fill_color = .{ .r = 0, .g = 0, .b = 0 },
            //         .x = @intCast(segment.start_x),
            //         .y = @intCast(cart.screen_height - segment.start_y),
            //         .width = 1 + segment.len,
            //         .height = 2,
            //     });
            // }
            cart.rect(.{
                .fill_color = .{ .r = 0, .g = 0, .b = 20 },
                .x = 0,
                .y = 0,
                .width = cart.screen_width,
                .height = cart.screen_height,
            });
            var state: bool = true;
            var y: u32 = 0;
            var x: u32 = 0;

            for (segments.flips) |flip| {
                var done: u32 = 0;
                while (done < flip) {
                    if (x + (flip - done) > cart.screen_width) {
                        noodle(x, y, cart.screen_width - x, state);
                        log("to end {},{}: {} of {}", .{ x, y, done, flip });
                        done += cart.screen_width - x;
                        y += 1;
                        x = 0;
                    } else {
                        noodle(x, y, flip, state);
                        log("some {},{}: {} of {}", .{ x, y, done, flip });
                        x += (flip - done);
                        done = flip;
                    }
                }
                state = !state;
            }
            // Dim
            // if (ticks % 2 == 0) {
            //     // {
            //     for (cart.framebuffer) |*col| {
            //         col.r = @intCast((@as(u32, @intCast(col.r)) * 101) / 100);
            //         col.g = @intCast((@as(u32, @intCast(col.g)) * 101) / 100);
            //         col.b = @intCast((@as(u32, @intCast(col.b)) * 101) / 100);
            //     }
            // }
        },
    }
}
