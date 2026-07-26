const std = @import("std");
const xcb = @import("xcb");

pub fn main() !void {
    const connection = xcb.connect(null, null) orelse return error.Connect;
    defer xcb.disconnect(connection);
    if (connection.has_error != 0) return error.Connect;

    const screen = xcb.setupRootsIterator(connection.setup).data.?.*;

    const window: xcb.Window = try connection.generateId();

    xcb.createWindow(
        connection,
        0,
        window,
        screen.root,
        0,
        0,
        300,
        300,
        1,
        xcb.window_class.copy_from_parent,
        screen.root_visual,
        xcb.cw.back_pixel | xcb.cw.event_mask,
        &.{
            0x00ff00ff,
            xcb.event_mask.exposure,
        },
    );

    xcb.mapWindow(connection, window);

    const _NET_WM_NAME = "_NET_WM_NAME";
    const UTF8_STRING = "UTF8_STRING";

    const net_wm_name_cookie = xcb.internAtom(connection, false, _NET_WM_NAME.len, _NET_WM_NAME);
    const utf8_string_cookie = xcb.internAtom(connection, false, UTF8_STRING.len, UTF8_STRING);

    _ = xcb.flush(connection);

    const net_wm_name = xcb.internAtomReply(connection, net_wm_name_cookie, null).atom;
    const utf8_string = xcb.internAtomReply(connection, utf8_string_cookie, null).atom;

    std.log.info("net_wm_name: {d} -> {d}", .{ net_wm_name_cookie.sequence, net_wm_name.id });
    std.log.info("utf8_string: {d} -> {d}", .{ utf8_string_cookie.sequence, utf8_string.id });

    const title = "Title!";

    xcb.changeProperty(
        connection,
        xcb.prop_mode.replace,
        window,
        .{ .id = xcb.atom.wm_name },
        .{ .id = xcb.atom.string },
        8,
        title.len,
        @ptrCast(title.ptr),
    );

    xcb.changeProperty(
        connection,
        xcb.prop_mode.replace,
        window,
        net_wm_name,
        utf8_string,
        8,
        title.len,
        @ptrCast(title.ptr),
    );

    _ = xcb.flush(connection);

    while (true) {
        const event = xcb.waitForEvent(connection) orelse break;

        switch (event.response_type & 0x7f) {
            xcb.Expose.opcode => {
                // redraw here
            },
            xcb.ClientMessage.opcode => {
                // window close handling
                break;
            },
            else => {},
        }
    }
}
