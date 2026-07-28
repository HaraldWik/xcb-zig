const builtin = @import("builtin");

const std = @import("std");

pub const Xid = packed struct(u32) {
    id: u32,

    pub const none: Xid = .{ .id = 0 };

    pub const GenerateIdError = error{
        Pthread,
        Deadlock,
        InvalidMutex,
        NotOwner,
    };
};

const Char = u8;

const Byte = u8;

const Card8 = u8;
const Card16 = u16;
const Card32 = u32;
const Card64 = u64;

const Int8 = i8;
const Int16 = i16;
const Int32 = i32;
const Int64 = i64;

pub const Connection = extern struct {
    has_error: c_int,

    // constant data
    setup: *const Setup,
    fd: c_int,

    // I/O data
    iolock: std.c.pthread_mutex_t,
    in: In,
    out: Out,

    // misc data
    ext: Ext,
    xid: IntXid,

    pub fn generateId(self: *Connection) Xid.GenerateIdError!Xid {
        switch (std.c.pthread_mutex_lock(&self.xid.lock)) {
            .SUCCESS => {},
            .DEADLK => return error.Deadlock,
            .INVAL => return error.InvalidMutex,
            else => return error.Pthread,
        }

        const id = self.xid.base | self.xid.last;
        self.xid.last += self.xid.inc;

        switch (std.c.pthread_mutex_unlock(&self.xid.lock)) {
            .SUCCESS => {},
            .PERM => return error.NotOwner,
            .INVAL => return error.InvalidMutex,
            else => return error.Pthread,
        }

        return .{ .id = id };
    }

    const Fd = extern struct {
        fd: [16]c_int,
        nfd: c_int,
        ifd: c_int,

        const have_sendmsg = switch (builtin.os.tag) {
            .linux,
            .freebsd,
            .openbsd,
            .netbsd,
            .dragonfly,
            .macos,
            .ios,
            .tvos,
            .watchos,
            .visionos,
            => true,

            else => false,
        };
    };

    pub const In = extern struct {
        event_cond: std.c.pthread_cond_t,

        reading: c_int,

        queue: [4096]u8,
        queue_len: c_int,

        request_expected: u64,
        request_read: u64,
        request_completed: u64,
        total_read: u64,
        current_reply: ?*anyopaque,
        current_reply_tail: ?*?*anyopaque,

        replies: ?*anyopaque,
        events: ?*anyopaque,
        events_tail: ?*?*anyopaque,
        readers: ?*anyopaque,
        special_waiters: ?*anyopaque,

        pending_replies: ?*anyopaque,
        pending_replies_tail: ?*?*anyopaque,

        in_fd: if (Fd.have_sendmsg) Fd else void,

        special_events: ?*anyopaque,
    };

    pub const Out = extern struct {
        cond: std.c.pthread_cond_t,
        writing: c_int,

        socket_cond: std.c.pthread_cond_t,
        return_socket: *const fn (closure: ?*anyopaque) callconv(.c) void,
        socket_closure: ?*anyopaque,
        socket_moving: c_int,

        queue: [16384]u8,
        queue_len: c_int,

        request: u64,
        request_written: u64,
        request_expected_written: u64,
        total_written: u64,

        reqlenlock: std.c.pthread_mutex_t,
        maximum_request_length_tag: c_int,
        maximum_request_length: extern union {
            cookie: Cookie(*anyopaque),
            value: u32,
        },
        out_fd: if (Fd.have_sendmsg) Fd else void,
    };

    pub const Ext = extern struct {
        lock: std.c.pthread_mutex_t,
        extensions: ?*anyopaque,
        extensions_size: c_int,
    };

    pub const IntXid = extern struct {
        lock: std.c.pthread_mutex_t,
        last: u32,
        base: u32,
        max: u32,
        inc: u32,
    };
};

pub fn Cookie(T: type) type {
    _ = T;
    return extern struct {
        sequence: u32,
    };
}

pub const GenericEvent = extern struct {
    response_type: u8,
    pad0: u8,
    sequence: u16,
    pad: [7]u32,
    full_sequence: u32,
};

pub const GenericError = extern struct {
    response_type: u8,
    error_code: u8,
    sequence: u16,
    resource_id: u32,
    minor_code: u16,
    major_code: u8,
    pad0: [21]u8,
    full_sequence: u32,
};

pub const ScreenIterator = extern struct {
    data: ?*Screen,
    rem: i32,
    index: i32,
};

extern "xcb" fn xcb_connect(displayname: ?[*:0]const u8, screenp: ?*i32) ?*Connection;
pub const connect = xcb_connect;
extern "xcb" fn xcb_disconnect(connection: *Connection) void;
pub const disconnect = xcb_disconnect;
extern "xcb" fn xcb_flush(connection: *Connection) i32;
pub const flush = xcb_flush;
extern "xcb" fn xcb_wait_for_event(connection: *Connection) ?*GenericEvent;
pub const waitForEvent = xcb_wait_for_event;
extern "xcb" fn xcb_poll_for_event(connection: *Connection) ?*GenericEvent;
pub const pollForEvent = xcb_poll_for_event;
extern "xcb" fn xcb_free_event(connection: *Connection, event: *GenericEvent) void;
pub const freeEvent = xcb_free_event;

extern "xcb" fn xcb_setup_roots_iterator(setup: *const Setup) ScreenIterator;
pub const setupRootsIterator = xcb_setup_roots_iterator;
