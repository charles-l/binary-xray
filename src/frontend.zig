const std = @import("std");
const shm = @import("shm.zig");

const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raygui.h");
});

pub fn main() !void {
    var queue = try shm.init_queue(false);
    defer shm.deinit_queue(queue);
    var last_end = queue.end;

    rl.InitWindow(800, 600, "covgui");

    var panel_scroll: rl.Vector2 = .{ .x = 0, .y = 0 };
    var panel_rec: rl.Rectangle = .{ .x = 20, .y = 40, .width = 200, .height = 150 };
    var panel_content_rec: rl.Rectangle = .{ .x = 0, .y = 0, .width = 340, .height = 340 };
    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.BLACK);

        var view = rl.GuiScrollPanel(panel_rec, null, panel_content_rec, &panel_scroll);

        rl.BeginScissorMode(@floatToInt(i32, view.x), @floatToInt(i32, view.y), @floatToInt(i32, view.width), @floatToInt(i32, view.height));
        _ = rl.GuiGrid(.{
            .x = panel_rec.x + panel_scroll.x,
            .y = panel_rec.y + panel_scroll.y,
            .width = panel_content_rec.width,
            .height = panel_content_rec.height,
        }, null, 16, 3);
        rl.EndScissorMode();

        if (last_end != queue.end) {
            std.debug.print("bb: 0x{x}\n", .{queue.bb_queue[queue.end]});
            last_end = queue.end;
        }
    }
}
