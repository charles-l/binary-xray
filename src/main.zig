const std = @import("std");
const testing = std.testing;
const c = @cImport({
    @cInclude("dr_api.h");
    @cInclude("drmgr.h");
});

const bfd = @cImport({
    @cInclude("bfd.h");
});

const assert = std.debug.assert;

export fn event_app_instruction(dr_context: ?*anyopaque, tag: ?*anyopaque, bb: ?*c.instrlist_t, inst: ?*c.instr_t, for_trace: u8, translating: u8, user_data: ?*anyopaque) c.dr_emit_flags_t {
    _ = inst;
    _ = for_trace;
    _ = translating;
    _ = user_data;
    _ = dr_context;
    _ = tag;

    var instr = c.instrlist_first_app(bb);
    while (instr != null) : (instr = c.instr_get_next_app(instr)) {
        var pc = c.instr_get_app_pc(instr);
        assert(pc != null);
        //if (@ptrToInt(pc) < 0x417bf0 and @ptrToInt(pc) > 0x416a8f) {
        if (addrlinemap.contains(@ptrToInt(pc))) {
            const lineno = addrlinemap.get(@ptrToInt(pc)) orelse 0;
            const i = linehitmap.get(lineno).?;
            linehitmap.put(lineno, i + 1) catch @panic("ded");
        }
        //std.debug.print("line: {any}\n", .{addrlinemap.get(@ptrToInt(pc))});
        //}
    }

    //c.instrlist_disassemble(dr_context, @ptrCast([*c]u8, tag), bb, 0);

    return c.DR_EMIT_DEFAULT;
}

export fn event_exit() void {
    //std.debug.print("{*}\n", .{pc});

    var it = linehitmap.iterator();
    while (it.next()) |kv| {
        std.debug.print("line {} hit {} times\n", .{ kv.key_ptr.*, kv.value_ptr.* });
    }
}

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

var linehitmap = std.AutoHashMap(u32, u64).init(gpa);
var addrlinemap = std.AutoHashMap(u64, u32).init(gpa);

extern fn hack_bfd_asymbol_value(sy: [*c]const bfd.asymbol) bfd.bfd_vma;

export fn dr_client_main(id: c.client_id_t, argc: i32, argv: [*][*]const u8) void {
    _ = id;
    _ = argc;
    _ = argv;
    {
        const r = c.drmgr_init();
        assert(r != 0);
    }

    {
        const r1 = bfd.bfd_init();
        assert(r1 != 0);

        //const r2 = bfd.bfd_set_default_target("x86_64-pc-linux-gnu");
        //assert(r2);

        const abfd = bfd.bfd_openr("/home/nc/projects/blobby/physics/physics.bin", null);
        assert(abfd != null);

        const object = 1;
        const r2 = bfd.bfd_check_format(abfd, object);
        assert(r2);

        const bfd_target = bfd.bfd_find_target("x86_64-pc-linux-gnu", abfd);
        assert(bfd_target != null);
        const upper_bound_bytes = bfd_target.*._bfd_get_symtab_upper_bound.?(abfd);

        var symbols_data = gpa.alignedAlloc(u8, 8, @intCast(usize, upper_bound_bytes)) catch @panic("oom");
        const sym_count = bfd_target.*._bfd_canonicalize_symtab.?(abfd, @ptrCast([*c][*c]bfd.asymbol, symbols_data));
        assert(sym_count >= 0);

        const symbols = @ptrCast([*c][*c]bfd.bfd_symbol, symbols_data)[0..@intCast(usize, sym_count)];
        std.debug.print("found {} symbols\n", .{sym_count});
        const target_function = "main.convex_convex_intersection_gjk-770";
        var symbol = lbl: {
            for (symbols) |s| {
                var name_slice = s.*.name[0..std.mem.len(s.*.name)];
                if (std.mem.eql(u8, name_slice, target_function)) {
                    break :lbl s;
                }
            }
            @panic("Couldn't find symbol");
        };

        var filename: [*c]u8 = undefined;
        var functionname: [*c]const u8 = target_function;
        var lineno: u32 = undefined;
        const r3 = bfd_target.*._bfd_find_line.?(abfd, &symbols[0], symbol, &filename, &lineno);
        var i: u64 = 0;
        assert(r3);
        var vm_offset = hack_bfd_asymbol_value(symbol.?);
        var dcontext = c.GLOBAL_DCONTEXT;
        while (std.mem.eql(u8, target_function, functionname[0..std.mem.len(functionname)])) : (i += @intCast(u64, c.decode_sizeof(dcontext, vm_offset + i, null, null))) {
            const r4 = bfd_target.*._bfd_find_nearest_line.?(
                abfd,
                &symbols[0],
                bfd.bfd_asymbol_section(symbol),
                symbol.*.value + i,
                &filename,
                &functionname,
                &lineno,
                null,
            );
            assert(r4);
            if (lineno != 0) {
                std.debug.print("{x}\n", .{vm_offset + i});
                addrlinemap.put(vm_offset + i, lineno) catch @panic("can't add addr key");
            }
        }
        var it = addrlinemap.iterator();
        while (it.next()) |kv| {
            linehitmap.put(kv.value_ptr.*, 0) catch @panic("can't add lineno key");
        }
        linehitmap.put(0, 0) catch unreachable; // for lines that don't appear
    }

    if (c.drmgr_register_bb_instrumentation_event(null, event_app_instruction, null) == 0) {
        unreachable();
    }
    c.dr_register_exit_event(event_exit);
}
