const std = @import("std");
const sdl = @import("sdl");

const paddle_height = 196;
const paddle_width = 32;
const ball_size: c_int = 48;
const ball_speed = 6.2;

const window_width = 1280;
const window_height = 720;

var rng: std.rand.Random = undefined;
var predicted: c_int = 0;


const CollisionSide = enum{
    Left,
    Right,
    Top,
    Bottom
};

const Ball = struct{
    x: f32,
    y: f32,

    dx: f32,
    dy: f32,
    speed: f32,

    collision_box: sdl.Rectangle,
};

const Paddle = struct{
    x: f32,
    y: f32,
    dy: c_int,

    collision_box: sdl.Rectangle,
    points: u32,
};

pub fn main() anyerror!void {
    rng = std.rand.Xoroshiro128.init(@intCast(u64, std.time.milliTimestamp())).random;

    try sdl.init(.{
        .video = true,
        .events = true,
        .audio = true,
    });
    defer sdl.quit();

    try sdl.image.init(.{
        .png = true,
    });
    defer sdl.image.quit();

    // create a window
    var window = try sdl.createWindow(
        "testing sdl",
        .centered,
        .centered,
        window_width,
        window_height,
        .{},
    );
    defer window.destroy();

    var renderer = try sdl.createRenderer(
        window,
        null,
        .{
            .accelerated = true,
            .present_vsync = true,
        }
    );
    defer renderer.destroy();

    const ball_sprite = try sdl.image.loadTexture(
        renderer,
        "./res/ball.png",
    );
    defer ball_sprite.destroy();

    const paddle_sprite = try sdl.image.loadTexture(
        renderer,
        "./res/paddle.png",
    );
    defer paddle_sprite.destroy();
    const paddle_info = try paddle_sprite.query();

    var window_size = window.getSize();
    
    const center_x = @divExact(window_size.width, 2);
    const center_y = @divExact(window_size.height, 2);

    const rand_angle = rng.float(f32)*2.0*std.math.pi;

    predicted = center_y;

    // place the center ball
    var ball = Ball{
        .x = @intToFloat(f32, center_x),
        .y = @intToFloat(f32, center_y),
        .speed = ball_speed,
        .dx = ball_speed * @cos(rand_angle),
        .dy = ball_speed * @sin(rand_angle),
        .collision_box = .{
            .x = center_x - @divFloor(ball_size, 2),
            .y = center_y - @divFloor(ball_size, 2),
            .width = ball_size,
            .height = ball_size
        },
    };

    var paddles = [_]Paddle{
        .{
            .x = 30.0,
            .y = @intToFloat(f32, center_y),
            .dy = 0,
            .collision_box = .{
                .x = 30 - @divFloor(@intCast(c_int, paddle_info.width), 2),
                .y = center_y - @divFloor(paddle_height, 2),
                .width = @intCast(c_int, paddle_info.width),
                .height = paddle_height
            },
            .points = 0,
        },
        .{
            .x = @intToFloat(f32, window_size.width) - 30.0,
            .y = @intToFloat(f32, center_y),
            .dy = 0,
            .collision_box = .{
                .x = (window_size.width - 30) - @divFloor(@intCast(c_int, paddle_info.width), 2),
                .y = center_y - @divFloor(paddle_height, 2),
                .width = @intCast(c_int, paddle_info.width),
                .height = paddle_height,
            },
            .points = 0,
        },
    };
    

    main_loop: while (true) {
        while (sdl.pollEvent()) |event| {
            switch (event) {
                .quit => break :main_loop,
                .key_down => |kev| {
                    switch (kev.keysym.sym) {
                        sdl.c.SDLK_ESCAPE => break :main_loop,
                        else => {},
                    }
                },
                else => {},
            }
        }

        window_size = window.getSize();
        
        const keystate = sdl.getKeyboardState();

        paddles[0].dy = 0;
        paddles[1].dy = 0;

        // if (keystate.isPressed(sdl.c.SDL_Scancode.SDL_SCANCODE_W))
        //     paddles[0].dy -= 1;
        // if (keystate.isPressed(sdl.c.SDL_Scancode.SDL_SCANCODE_S))
        //     paddles[0].dy += 1;
        const y_exact = @floatToInt(c_int, paddles[0].y);
        if ((try std.math.absInt(predicted - y_exact)) > 3) {
            paddles[0].dy += negateIfTrue(y_exact > predicted);
        }

        if (keystate.isPressed(sdl.c.SDL_Scancode.SDL_SCANCODE_UP))
            paddles[1].dy -= 1;
        if (keystate.isPressed(sdl.c.SDL_Scancode.SDL_SCANCODE_DOWN))
            paddles[1].dy += 1;

        for (paddles) |*paddle| {
            movePaddle(paddle, 5);
        }

        moveBall(&ball, paddles[0..]);

        // Clear the screen to a very dark gray
        try renderer.setColor(sdl.Color.rgb(0x10, 0x10, 0x10));
        try renderer.clear();

        try renderer.copy(
            ball_sprite,
            ball.collision_box,
            null,
        );
        for (paddles) |paddle| {
            try renderer.copy(
                paddle_sprite,
                paddle.collision_box,
                null,
            );
        }

        // Present the screen contents
        renderer.present();
    }
}

fn movePaddle(paddle: *Paddle, speed: c_int) void {
    if (
        (paddle.collision_box.y+(paddle.dy*speed) > 0) and
        (paddle.collision_box.y+paddle_height+(paddle.dy*speed) < window_height)
    ) {
        paddle.*.y += @intToFloat(f32, paddle.dy*speed);
        paddle.*.collision_box.y = @floatToInt(c_int, paddle.y) - @divFloor(paddle_height, 2);
    }
}

fn checkCollision(ball: *Ball, paddles: *[2]Paddle) ?CollisionSide {

    if (ball.collision_box.y < 0)
        return CollisionSide.Top;
    if (ball.collision_box.y + ball_size > window_height)
        return CollisionSide.Bottom;

    if (
        (ball.collision_box.x > @floatToInt(c_int, paddles[0].x)+@divFloor(paddle_width, 2)) and
        (ball.collision_box.x + ball_size < @floatToInt(c_int, paddles[1].x)-@divFloor(paddle_width, 2))
    ) {
        return null;
    } else {
        if (ball.x < 640)  {
            if (
                (ball.collision_box.y+ball_size < paddles[0].collision_box.y) or
                (ball.collision_box.y > (paddles[0].collision_box.y+paddle_height))
            ) {
                return null;
            } else {
                return CollisionSide.Left;
            }
        } else {
            if (
                (ball.collision_box.y+ball_size < paddles[1].collision_box.y) or
                (ball.collision_box.y > (paddles[1].collision_box.y+paddle_height))
            ) {
                return null;
            } else {
                return CollisionSide.Right;
            }
        }
    }
}

fn moveBall(ball: *Ball, paddles: *[2]Paddle) void {
    if (checkCollision(ball, paddles)) |side| {
        switch(side) {
            CollisionSide.Left, CollisionSide.Right => {
                ball.speed += 0.5;

                var paddle: usize = 0;
                if (side == CollisionSide.Right) paddle = 1;

                const relative_y = paddles[paddle].y - ball.y;
                const degrees_per_pixel = 60.0/(paddle_height/2.0);

                const new_angle = (degrees_per_pixel*relative_y*std.math.pi)/180.0;

                var negate: f32 = 1;
                if (side == CollisionSide.Right) negate = -1;

                ball.dx = negate*ball.speed * @cos(new_angle);
                ball.dy = ball.speed * @sin(new_angle);

                // total vertical travel between paddles

                // predicts jiggles
                if (side == CollisionSide.Right) {
                    const distance = (paddles[1].x - paddles[0].x)+@intToFloat(f32, paddle_width);

                    const screen_height = @intToFloat(f32, window_height);

                    const slope = ball.dy/ball.dx;
                    var predicted_y = std.math.absFloat(slope * (distance) + ball.y);
                    const bounces = std.math.absFloat(@divFloor(predicted_y, screen_height));

                    if (@mod(@floatToInt(c_int, bounces), 2) == 0) {
                        predicted_y = @mod(predicted_y, screen_height);
                    } else {
                        predicted_y = screen_height - @mod(predicted_y, screen_height);
                    }

                    std.log.info("predicted y value: {d}", .{predicted_y});
                    predicted = @floatToInt(c_int, predicted_y);
                }
                
                // std.log.info("speed: {d}", .{ball.speed});
            },
            CollisionSide.Top, CollisionSide.Bottom => {
                ball.dy = -ball.dy;
            }
        }
    }

    ball.x += ball.dx;
    ball.y -= ball.dy;

    if (ball.collision_box.x < 0 or ball.collision_box.x + ball_size > window_width) {
        if(ball.x < 0) {
            paddles[1].points += 1;
        } else {
            paddles[0].points += 1;
        }

        std.log.info("Score\t{} : {}", .{paddles[0].points, paddles[1].points});

        const rand_angle = rng.float(f32)*2.0*std.math.pi;
        ball.x = @intToFloat(f32, window_width)/2.0;
        ball.y = @intToFloat(f32, window_height)/2.0;
        ball.speed = ball_speed;
        ball.dx = ball_speed*@cos(rand_angle);
        ball.dy = ball_speed*@sin(rand_angle);
    }

    ball.collision_box.x = @floatToInt(c_int, ball.x) - @divFloor(ball_size, 2);
    ball.collision_box.y = @floatToInt(c_int, ball.y) - @divFloor(ball_size, 2);
    
}

fn negateIfTrue(condition: bool) c_int {
    if (condition)
        return -1;
    
    return 1;
}