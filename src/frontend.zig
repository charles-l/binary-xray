const std = @import("std");
const shm = @import("shm.zig");

const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raygui.h");
});

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

fn rebuild_bb_line_map(queue: *shm.Queue, map: *std.AutoHashMap(u64, std.ArrayList(u32))) !void {
    for (queue.line_pairs.constSlice()) |p| {
        if (map.contains(p.addr)) {
            var l = map.getPtr(p.addr).?;
            if (std.mem.indexOfScalar(u32, l.items, p.line) == null) {
                try l.append(p.line);
            }
        } else {
            var a = std.ArrayList(u32).init(gpa);
            try a.append(p.line);
            try map.put(p.addr, a);
        }
    }
}

pub fn main() !void {
    var queue = try shm.init_queue(false);
    defer shm.deinit_queue(queue, false);

    var last_end = queue.end;

    var bb_line_map = std.AutoHashMap(u64, std.ArrayList(u32)).init(gpa);
    try rebuild_bb_line_map(queue, &bb_line_map);

    const window_width = 800;
    const window_height = 800;

    rl.InitWindow(window_width, window_height, "covgui");

    var panel_scroll: rl.Vector2 = .{ .x = 0, .y = 0 };
    var panel_rec: rl.Rectangle = .{ .x = 0, .y = 0, .width = @divExact(window_width, 2), .height = window_height };

    const source_text = lbl: {
        const file = try std.fs.openFileAbsolute("/home/nc/projects/blobby/physics/main.odin", .{ .mode = .read_only });
        defer file.close();

        break :lbl try file.readToEndAllocOptions(gpa, 20000, null, 1, 0);
    };

    const newline = "\n";
    const line_count = std.mem.count(u8, source_text, newline);
    const line_offsets = lbl: {
        var line_offsets = try gpa.alloc(usize, line_count);
        var i: usize = 0;
        var j: usize = 0;
        while (i < source_text.len) : (i += 1) {
            if (std.mem.eql(u8, source_text[i .. i + 2], newline)) {
                line_offsets[j] = i;
                j += 1;
            }
        }
        break :lbl line_offsets;
    };
    _ = line_offsets;

    var brightness = try gpa.alloc(u8, line_count);

    const text_size = rl.MeasureTextEx(rl.GetFontDefault(), source_text, 10, 1);
    var panel_content_rec: rl.Rectangle = .{ .x = 0, .y = 0, .width = text_size.x, .height = text_size.y };

    rl.SetTargetFPS(60);

    while (!rl.WindowShouldClose()) {
        if (last_end != queue.end) {
            var addr = queue.bb_queue[queue.end];
            if (!bb_line_map.contains(addr)) {
                // HACK: rebuilding this table as needed
                try rebuild_bb_line_map(queue, &bb_line_map);
            }

            if (bb_line_map.get(addr)) |lines| {
                for (lines.items) |line| {
                    brightness[line] = 255;
                }
                std.debug.print("bb: 0x{x} -> {any}\n", .{ addr, lines.items });
            } else {
                std.debug.print("bb: 0x{x} -> UNKNOWN\n", .{addr});
            }
            last_end = queue.end;
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.BLACK);

        var view = rl.GuiScrollPanel(panel_rec, null, panel_content_rec, &panel_scroll);

        rl.BeginScissorMode(@floatToInt(i32, view.x), @floatToInt(i32, view.y), @floatToInt(i32, view.width), @floatToInt(i32, view.height));
        const bx = @floatToInt(i32, panel_rec.x + panel_scroll.x) + 5;
        const by = @floatToInt(i32, panel_rec.y + panel_scroll.y) + 5;

        for (brightness) |*b, i| {
            if (b.* > 0) {
                b.* -= 1;
                rl.DrawRectangle(bx, by + 15 * @intCast(i32, i), 100, 15, rl.Fade(rl.GRAY, @intToFloat(f32, b.*) / 255));
            }
        }

        rl.DrawText(source_text, bx, by, 10, rl.BLACK);
        //_ = rl.GuiGrid(.{
        //    .x = panel_rec.x + panel_scroll.x,
        //    .y = panel_rec.y + panel_scroll.y,
        //    .width = panel_content_rec.width,
        //    .height = panel_content_rec.height,
        //}, null, 16, 3);
        rl.EndScissorMode();
    }
}
