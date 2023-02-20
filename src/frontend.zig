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

    std.debug.print("filename::: {s}\n", .{queue.filename.slice()});

    var bb_line_map = std.AutoHashMap(u64, std.ArrayList(u32)).init(gpa);
    try rebuild_bb_line_map(queue, &bb_line_map);

    const window_width = 800;
    const window_height = 800;

    rl.InitWindow(window_width, window_height, "bxgui");
    rl.SetWindowState(rl.FLAG_WINDOW_RESIZABLE);

    var panel_scroll: rl.Vector2 = .{ .x = 0, .y = 0 };

    const source_text = lbl: {
        const file = try std.fs.openFileAbsolute(queue.filename.constSlice(), .{ .mode = .read_only });
        defer file.close();

        break :lbl try file.readToEndAllocOptions(gpa, 20000, null, 1, 0);
    };

    const newline = "\n";
    const line_count = std.mem.count(u8, source_text, newline);

    // character offsets of lines in text
    const line_offsets = lbl: {
        var line_offsets = try gpa.alloc(usize, line_count + 1);
        line_offsets[0] = 0;
        var i: usize = 0;
        var j: usize = 1;
        while (i < source_text.len) : (i += 1) {
            if (std.mem.eql(u8, source_text[i .. i + newline.len], newline)) {
                line_offsets[j] = i;
                j += 1;
            }
        }
        line_offsets[line_offsets.len - 1] = source_text.len;
        break :lbl line_offsets;
    };

    var brightness = try gpa.alloc(u8, line_count);

    const font_size = 14;
    var font = rl.LoadFontEx("font/iAWriterMonoS-Regular.ttf", font_size, null, 256);
    const char_width = rl.MeasureTextEx(font, "AAAAAAAAAA", font_size, 1).x / 10;

    const text_size = rl.MeasureTextEx(font, source_text, font_size, 1);
    var panel_content_rec: rl.Rectangle = .{ .x = 0, .y = 0, .width = text_size.x, .height = text_size.y };

    const line_height = @floatToInt(i32, font_size * 1.5);

    rl.SetTargetFPS(60);

    while (!rl.WindowShouldClose()) {
        var panel_rec: rl.Rectangle = .{ .x = 0, .y = 0, .width = @intToFloat(f32, rl.GetScreenWidth()), .height = @intToFloat(f32, rl.GetScreenHeight()) };

        while (queue.readNext()) |addr| {
            if (!bb_line_map.contains(addr)) {
                // HACK: rebuilding this table as needed
                try rebuild_bb_line_map(queue, &bb_line_map);
            }

            if (bb_line_map.get(addr)) |lines| {
                for (lines.items) |line| {
                    brightness[line - 1] = 255;
                }
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
        const bx = panel_rec.x + panel_scroll.x + 5;
        const by = panel_rec.y + panel_scroll.y + 5;

        for (brightness) |*b, i| {
            if (b.* > 0) {
                b.* -= 5;
                const chars = @intToFloat(f32, line_offsets[i + 1] - line_offsets[i]);
                rl.DrawRectangle(
                    @floatToInt(i32, bx),
                    @floatToInt(i32, by + @intToFloat(f32, line_height) * @intToFloat(f32, i) - 3),
                    @floatToInt(i32, chars * char_width),
                    line_height,
                    rl.Fade(rl.BLUE, @intToFloat(f32, b.*) / 255),
                );
            }
        }

        rl.DrawTextEx(font, source_text, .{ .x = bx, .y = by }, font_size, 1, rl.BLACK);
        rl.EndScissorMode();
    }
}
