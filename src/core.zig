pub const Xid = packed struct(u32) {
    id: u32,

    pub const none: Xid = .{ .id = 0 };
};

const Bool = enum(u8) {
    false = 0,
    true = 1,
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

pub const Connection = *opaque {
    // pub fn generateId(self: Connection) Xid {
    //     return .none;
    // }
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

extern "xcb" fn xcb_connect(displayname: ?[*:0]const u8, screenp: ?*i32) ?Connection;
pub const connect = xcb_connect;
extern "xcb" fn xcb_disconnect(connection: Connection) void;
pub const disconnect = xcb_disconnect;
extern "xcb" fn xcb_connection_has_error(connection: Connection) i32;
pub const connectionHasError = xcb_connection_has_error;
extern "xcb" fn xcb_flush(connection: Connection) i32;
pub const flush = xcb_flush;
extern "xcb" fn xcb_get_setup(connection: Connection) *const Setup;
pub const getSetup = xcb_get_setup;
extern "xcb" fn xcb_get_file_descriptor(connection: Connection) i32;
pub const getFileDescriptor = xcb_get_file_descriptor;
extern "xcb" fn xcb_wait_for_event(connection: Connection) ?*GenericEvent;
pub const waitForEvent = xcb_wait_for_event;
extern "xcb" fn xcb_poll_for_event(connection: Connection) ?*GenericEvent;
pub const pollForEvent = xcb_poll_for_event;
extern "xcb" fn xcb_setup_roots_iterator(setup: *const Setup) ScreenIterator;
pub const setupRootsIterator = xcb_setup_roots_iterator;
