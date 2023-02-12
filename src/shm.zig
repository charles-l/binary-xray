const c = @cImport({
    @cInclude("sys/mman.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("pthread.h");
});

const std = @import("std");

pub const queue = struct {
    const capacity = 2048;

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

pub fn init_queue(write: bool) !*queue {
    var fd = c.shm_open("/covring", (if (write) c.O_RDWR else c.O_RDONLY) | c.O_CREAT, c.S_IRUSR | c.S_IWUSR);
    if (fd == -1) {
        return error.FailedToOpenSHM;
    }

    var mmap_mode = c.PROT_READ;
    if (write) {
        if (c.ftruncate(fd, @sizeOf(queue)) == -1) {
            return error.FailedToFtruncate;
        }
        mmap_mode |= c.PROT_WRITE;
    }

    var ptr = @ptrCast(*queue, @alignCast(8, c.mmap(null, @sizeOf(queue), mmap_mode, c.MAP_SHARED, fd, 0)));
    if (ptr == c.MAP_FAILED) {
        return error.FailedToMMAP;
    }
    return ptr;
}

pub fn deinit_queue(queue_ptr: *queue) void {
    _ = c.munmap(queue_ptr, @sizeOf(queue));
    _ = c.shm_unlink("/covring");
}
