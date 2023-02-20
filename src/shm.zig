const c = @cImport({
    @cInclude("sys/mman.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("pthread.h");
});

const std = @import("std");

pub const Queue = struct {
    const AddrLinePair = struct {
        addr: u64,
        line: u32,
    };
    const capacity = 2048;
    const max_lines = 4096;

    filename: std.BoundedArray(u8, 512),
    line_pairs: std.BoundedArray(AddrLinePair, max_lines),

    // https://www.bo-yang.net/2016/07/27/shared-memory-ring-buffer
    //lock: c.pthread_mutex_t,
    //begin: usize,

    end: std.atomic.Atomic(usize),
    read: std.atomic.Atomic(usize),

    bb_queue: [capacity]u64,

    pub fn add(self: *@This(), addr: u64) !void {
        const e = self.end.load(.SeqCst);
        self.bb_queue[e] = addr;
        self.end.store((e + 1) % self.bb_queue.len, .SeqCst);

        if (self.end.load(.SeqCst) == self.read.load(.SeqCst)) {
            return error.OverranRead;
        }
    }

    pub fn readNext(self: *@This()) ?u64 {
        const r = self.read.load(.SeqCst);
        const next = (r + 1) % self.bb_queue.len;

        if (next == self.end.load(.SeqCst)) {
            return null;
        } else {
            self.read.store(next, .SeqCst);
            return self.bb_queue[next];
        }
    }
};

pub fn init_queue(write: bool) !*Queue {
    var open_flags = if (write) c.O_RDWR | c.O_CREAT | c.O_EXCL else c.O_RDWR;
    var mmap_mode = c.PROT_WRITE | c.PROT_READ;

    var fd = c.shm_open("/bxdata", open_flags, c.S_IRUSR | c.S_IWUSR);
    if (fd == -1) {
        return error.FailedToOpenSHM;
    }

    if (write) {
        if (c.ftruncate(fd, @sizeOf(Queue)) == -1) {
            return error.FailedToFtruncate;
        }
    }

    var ptr = @ptrCast(*Queue, @alignCast(8, c.mmap(null, @sizeOf(Queue), mmap_mode, c.MAP_SHARED, fd, 0)));
    if (ptr == c.MAP_FAILED) {
        return error.FailedToMMAP;
    }

    return ptr;
}

pub fn deinit_queue(queue_ptr: *Queue, delete: bool) void {
    _ = c.munmap(queue_ptr, @sizeOf(Queue));
    if (delete) {
        _ = c.shm_unlink("/bxdata");
    }
}
