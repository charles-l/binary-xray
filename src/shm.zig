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

    running: bool,
    line_pairs: std.BoundedArray(AddrLinePair, max_lines),

    //https://www.bo-yang.net/2016/07/27/shared-memory-ring-buffer
    //lock: c.pthread_mutex_t,
    //begin: usize,

    end: usize,

    bb_queue: [capacity]u64,

    pub fn add(self: *@This(), addr: u64) void {
        self.bb_queue[self.end] = addr;
        self.end = (self.end + 1) % self.bb_queue.len;
        //if (self.end == self.begin) {
        //    std.debug.print("queue overran begin\n", .{});
        //    self.begin = (self.begin + 1) % self.bb_queue.len;
        //}
    }
};

pub fn init_queue(write: bool) !*Queue {
    var open_flags = if (write) c.O_RDWR | c.O_CREAT | c.O_EXCL else c.O_RDONLY;
    var mmap_mode = if (write) c.PROT_WRITE | c.PROT_READ else c.PROT_READ;

    var fd = c.shm_open("/covring", open_flags, c.S_IRUSR | c.S_IWUSR);
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
        _ = c.shm_unlink("/covring");
    }
}
