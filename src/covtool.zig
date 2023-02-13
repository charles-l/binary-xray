const std = @import("std");
const testing = std.testing;
const c = @cImport({
    @cInclude("dr_api.h");
    @cInclude("drmgr.h");
});

const shm = @import("shm.zig");

const bfd = @cImport({
    @cInclude("bfd.h");
});

const assert = std.debug.assert;

export fn trace_bb(addr: u64) void {
    const i = bb_addr_count.get(addr).?;
    bb_addr_count.put(addr, i + 1) catch unreachable;

    shm_queue_ptr.add(addr);
}

export fn event_app_instruction(dr_context: ?*anyopaque, tag: ?*anyopaque, bb: ?*c.instrlist_t, inst: ?*c.instr_t, for_trace: u8, translating: u8, user_data: ?*anyopaque) c.dr_emit_flags_t {
    _ = for_trace;
    _ = translating;
    _ = user_data;
    _ = tag;

    if (c.drmgr_is_first_instr(dr_context, inst) == 0) {
        return c.DR_EMIT_DEFAULT;
    }

    var instr = c.instrlist_first_app(bb);
    var first_pc = c.instr_get_app_pc(instr);
    var lines = std.ArrayList(u32).init(gpa);
    while (instr != null) : (instr = c.instr_get_next_app(instr)) {
        var pc = c.instr_get_app_pc(instr);
        assert(pc != null);
        if (instr_line_map.contains(@ptrToInt(pc))) {
            const lineno = instr_line_map.get(@ptrToInt(pc)) orelse 0;
            if (std.mem.indexOfScalar(u32, lines.items, lineno) == null) {
                lines.append(lineno) catch @panic("blah");
            }
        }
    }

    if (lines.items.len > 0) {
        for (lines.items) |line| {
            shm_queue_ptr.line_pairs.append(.{ .addr = @ptrToInt(first_pc), .line = line }) catch @panic("too many lines, increase Queue.max_lines");
        }
        std.debug.print("tracking bb 0x{x} which executes lines {any}\n", .{ @ptrToInt(first_pc), lines.items });

        c.dr_insert_clean_call(dr_context, bb, c.instrlist_first(bb), @intToPtr(*anyopaque, @ptrToInt(&trace_bb)), 0, 1, c.OPND_CREATE_INT64(first_pc));
        if (bb_addr_line_map.get(@ptrToInt(first_pc))) |old| {
            // check for unexpected duplicated bb
            assert(std.mem.eql(u32, old, lines.items));
            lines.deinit();
        } else {
            bb_addr_line_map.put(@ptrToInt(first_pc), lines.toOwnedSlice() catch @panic("ded")) catch @panic("couldn't add addrs");
            bb_addr_count.put(@ptrToInt(first_pc), 0) catch @panic("couldn't add addr");
        }
    }

    return c.DR_EMIT_DEFAULT;
}

var shm_queue_ptr: *shm.Queue = undefined;

export fn event_exit() void {
    var it = bb_addr_count.iterator();
    while (it.next()) |kv| {
        std.debug.print("bb 0x{x} hit {} times, lines {any}\n", .{ kv.key_ptr.*, kv.value_ptr.*, bb_addr_line_map.get(kv.key_ptr.*).? });
    }

    shm.deinit_queue(shm_queue_ptr, true);
}

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

var instr_line_map = std.AutoHashMap(u64, u32).init(gpa);
var bb_addr_line_map = std.AutoHashMap(u64, []u32).init(gpa);
var bb_addr_count = std.AutoHashMap(u64, u32).init(gpa);

extern fn hack_bfd_asymbol_value(sy: [*c]const bfd.asymbol) bfd.bfd_vma;

export fn dr_client_main(id: c.client_id_t, argc: i32, argv: [*c][*c]const u8) void {
    _ = id;
    _ = argc;
    _ = argv;

    shm_queue_ptr = shm.init_queue(true) catch @panic("failed to init queue");
    {
        const r = c.drmgr_init();
        assert(r != 0);
    }

    {
        const r1 = bfd.bfd_init();
        assert(r1 != 0);

        // TODO: look into using drsym_enumerate_lines and dropping libbfd
        const abfd = bfd.bfd_openr("/home/nc/projects/blobby/physics/physics.bin", null);
        assert(abfd != null);

        const object = 1;
        const r2 = bfd.bfd_check_format(abfd, object);
        assert(r2);

        const bfd_target = bfd.bfd_find_target(null, abfd);
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

        { // find starting line
            const r3 = bfd_target.*._bfd_find_line.?(abfd, &symbols[0], symbol, &filename, &lineno);
            assert(r3);
        }

        var vm_offset = hack_bfd_asymbol_value(symbol.?);
        var dcontext = c.GLOBAL_DCONTEXT;

        var i: u64 = 0;
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
                instr_line_map.put(vm_offset + i, lineno) catch @panic("can't add addr key");
            }
        }
    }

    if (c.drmgr_register_bb_instrumentation_event(null, event_app_instruction, null) == 0) {
        unreachable();
    }
    c.dr_register_exit_event(event_exit);
}
