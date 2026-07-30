const xcb_zig = @This();

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

pub const Connection = *opaque {};

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

pub const Extension = extern struct {
    name: [*:0]const u8,
    global_id: i32,
};

pub const ScreenIterator = extern struct {
    data: [*c]if (@hasDecl(xcb_zig, "Screen")) xcb_zig.Screen else extern struct {},
    rem: i32,
    index: i32,
};

pub const BaseDispatch = struct {
    xcb_connect: ?*const fn (displayname: ?[*:0]const u8, screenp: ?*i32) callconv(.c) ?Connection = null,
    xcb_connect_to_fd: ?*const fn (fd: i32, auth_info: ?*anyopaque) callconv(.c) ?Connection = null,
    xcb_connect_to_display_with_auth_info: ?*const fn (displayname: ?[*:0]const u8, auth_info: ?*anyopaque, screenp: ?*i32) callconv(.c) ?Connection = null,
    xcb_disconnect: ?*const fn (connection: Connection) callconv(.c) void = null,
    xcb_connection_has_error: ?*const fn (connection: Connection) callconv(.c) i32 = null,
    xcb_get_file_descriptor: ?*const fn (connection: Connection) callconv(.c) i32 = null,
    xcb_get_setup: ?*const fn (connection: Connection) callconv(.c) *const if (@hasDecl(xcb_zig, "Screen")) xcb_zig.Setup else anyopaque = null,
    xcb_generate_id: ?*const fn (connection: Connection) callconv(.c) Xid = null,
    xcb_flush: ?*const fn (connection: Connection) callconv(.c) i32 = null,
    xcb_send_request: ?*const fn (connection: Connection, flags: u32, vector: ?*anyopaque, request: ?*anyopaque) callconv(.c) u32 = null,
    xcb_send_request_with_fds: ?*const fn (connection: Connection, flags: u32, vector: ?*anyopaque, request: ?*anyopaque, numFds: u32, fds: [*]const i32) callconv(.c) u32 = null,
    xcb_wait_for_event: ?*const fn (connection: Connection) callconv(.c) ?*GenericEvent = null,
    xcb_poll_for_event: ?*const fn (connection: Connection) callconv(.c) ?*GenericEvent = null,
    xcb_poll_for_queued_event: ?*const fn (connection: Connection) callconv(.c) ?*GenericEvent = null,
    xcb_free_event: ?*const fn (connection: Connection, event: *GenericEvent) callconv(.c) void = null,
    xcb_wait_for_reply: ?*const fn (connection: Connection, request: u32, err: ?*?*GenericError) callconv(.c) ?*anyopaque = null,
    xcb_poll_for_reply: ?*const fn (connection: Connection, request: u32, reply: ?*?*anyopaque, err: ?*?*GenericError) callconv(.c) i32 = null,
    xcb_discard_reply: ?*const fn (connection: Connection, request: u32) callconv(.c) void = null,
    xcb_prefetch_extension_data: ?*const fn (connection: Connection, extension: *const Extension) callconv(.c) void = null,
    xcb_get_extension_data: ?*const fn (connection: Connection, extension: *const Extension) callconv(.c) *const if (@hasDecl(xcb_zig, "Screen")) xcb_zig.QueryExtensionReply else anyopaque = null,
    xcb_prefetch_maximum_request_length: ?*const fn (connection: Connection) callconv(.c) void = null,
    xcb_get_maximum_request_length: ?*const fn (connection: Connection) callconv(.c) u32 = null,
};

pub const BaseWrapper = BaseWrapperWithCustomDispatch(BaseDispatch);
pub fn BaseWrapperWithCustomDispatch(DispatchType: type) type {
    return struct {
        const Self = @This();
        pub const Dispatch = DispatchType;

        dispatch: Dispatch,

        pub fn load(dynlib: *std.DynLib) Self {
            var self: Self = .{ .dispatch = .{} };
            inline for (std.meta.fields(Dispatch)) |field| {
                if (dynlib.lookup(field.type, field.name)) |cmd_ptr| {
                    @field(self.dispatch, field.name) = @ptrCast(cmd_ptr);
                }
            }
            return self;
        }

        pub fn connect(self: Self, displayname: ?[*:0]const u8, screenp: ?*i32) ?Connection {
            return self.dispatch.xcb_connect.?(displayname, screenp);
        }
        pub fn connectToFd(self: Self, fd: i32, authInfo: ?*anyopaque) ?Connection {
            return self.dispatch.xcb_connect_to_fd.?(fd, authInfo);
        }
        pub fn connectToDisplayWithAuthInfo(self: Self, displayname: ?[*:0]const u8, authInfo: ?*anyopaque, screenp: ?*i32) ?Connection {
            return self.dispatch.xcb_connect_to_display_with_auth_info.?(displayname, authInfo, screenp);
        }
        pub fn disconnect(self: Self, connection: Connection) void {
            self.dispatch.xcb_disconnect.?(connection);
        }
        pub fn connectionHasError(self: Self, connection: Connection) i32 {
            return self.dispatch.xcb_connection_has_error.?(connection);
        }
        pub fn getFileDescriptor(self: Self, connection: Connection) i32 {
            return self.dispatch.xcb_get_file_descriptor.?(connection);
        }
        pub fn getSetup(self: Self, connection: Connection) *const if (@hasDecl(xcb_zig, "Screen")) xcb_zig.Setup else anyopaque {
            return self.dispatch.xcb_get_setup.?(connection);
        }
        pub fn generateId(self: Self, connection: Connection) Xid {
            return self.dispatch.xcb_generate_id.?(connection);
        }
        pub fn flush(self: Self, connection: Connection) i32 {
            return self.dispatch.xcb_flush.?(connection);
        }
        pub fn sendRequest(self: Self, connection: Connection, flags: u32, vector: ?*anyopaque, request: ?*anyopaque) u32 {
            return self.dispatch.xcb_send_request.?(connection, flags, vector, request);
        }
        pub fn sendRequestWithFds(self: Self, connection: Connection, flags: u32, vector: ?*anyopaque, request: ?*anyopaque, numFds: u32, fds: [*]const i32) u32 {
            return self.dispatch.xcb_send_request_with_fds.?(connection, flags, vector, request, numFds, fds);
        }
        pub fn waitForEvent(self: Self, connection: Connection) ?*GenericEvent {
            return self.dispatch.xcb_wait_for_event.?(connection);
        }
        pub fn pollForEvent(self: Self, connection: Connection) ?*GenericEvent {
            return self.dispatch.xcb_poll_for_event.?(connection);
        }
        pub fn pollForQueuedEvent(self: Self, connection: Connection) ?*GenericEvent {
            return self.dispatch.xcb_poll_for_queued_event.?(connection);
        }
        pub fn freeEvent(self: Self, connection: Connection, event: *GenericEvent) void {
            self.dispatch.xcb_free_event.?(connection, event);
        }
        pub fn waitForReply(self: Self, connection: Connection, request: u32, err: ?*?*GenericError) ?*anyopaque {
            return self.dispatch.xcb_wait_for_reply.?(connection, request, err);
        }
        pub fn pollForReply(self: Self, connection: Connection, request: u32, reply: ?*?*anyopaque, err: ?*?*GenericError) i32 {
            return self.dispatch.xcb_poll_for_reply.?(connection, request, reply, err);
        }
        pub fn discardReply(self: Self, connection: Connection, request: u32) void {
            self.dispatch.xcb_discard_reply.?(connection, request);
        }
        pub fn prefetchExtensionData(self: Self, connection: Connection, extension: *const Extension) void {
            self.dispatch.xcb_prefetch_extension_data.?(connection, extension);
        }
        pub fn getExtensionData(self: Self, connection: Connection, extension: *const Extension) *const anyopaque {
            return self.dispatch.xcb_get_extension_data.?(connection, extension);
        }
        pub fn prefetchMaximumRequestLength(self: Self, connection: Connection) void {
            self.dispatch.xcb_prefetch_maximum_request_length.?(connection);
        }
        pub fn getMaximumRequestLength(self: Self, connection: Connection) u32 {
            return self.dispatch.xcb_get_maximum_request_length.?(connection);
        }
    };
}

pub fn setupRootsIterator(setup: *const if (@hasDecl(xcb_zig, "Screen")) xcb_zig.Setup else anyopaque) ScreenIterator {
    if (!@hasDecl(xcb_zig, "Screen")) {
        @compileError("xcb Screen type is required for setupRootsIterator");
    }

    const screens: [*]xcb_zig.Screen = @ptrCast(@alignCast(
        @as([*]u8, @ptrCast(@constCast(setup))) + @sizeOf(xcb_zig.Setup),
    ));

    return .{
        .data = screens,
        .rem = setup.roots_len,
        .index = 0,
    };
}
