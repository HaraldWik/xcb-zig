const std = @import("std");
const xcb = @import("xcb");

pub fn main() !void {
    var libxcb = try std.DynLib.openZ("libxcb.so");
    defer libxcb.close();

    const bs: xcb.BaseWrapper = .load(&libxcb);
    const cr: xcb.CoreWrapper = .load(&libxcb);

    const connection = bs.connect(null, null) orelse return error.Connect;
    defer bs.disconnect(connection);
    if (bs.connectionHasError(connection) != 0) return error.Connect;

    const setup = bs.getSetup(connection);
    const screen = xcb.setupRootsIterator(setup).data.?.*;

    const window: xcb.Window = bs.generateId(connection);
    cr.createWindow(
        connection,
        0,
        window,
        screen.root,
        0,
        0,
        300,
        300,
        1,
        xcb.WINDOW_CLASS.copy_from_parent,
        screen.root_visual,
        xcb.CW.back_pixel | xcb.CW.event_mask,
        &.{
            0x00ff00ff,
            xcb.EVENT_MASK.exposure | xcb.EVENT_MASK.key_press | xcb.EVENT_MASK.key_release,
        },
    );

    cr.mapWindow(connection, window);

    const _NET_WM_NAME = "_NET_WM_NAME";
    const UTF8_STRING = "UTF8_STRING";

    const net_wm_name_cookie = cr.internAtom(connection, false, _NET_WM_NAME.len, _NET_WM_NAME);
    const utf8_string_cookie = cr.internAtom(connection, false, UTF8_STRING.len, UTF8_STRING);

    _ = bs.flush(connection);

    const net_wm_name = cr.internAtomReply(connection, net_wm_name_cookie, null).atom; // this is broken
    const utf8_string = cr.internAtomReply(connection, utf8_string_cookie, null).atom; // this is broken

    std.log.info("net_wm_name: {d} -> {d}", .{ net_wm_name_cookie.sequence, net_wm_name.id });
    std.log.info("utf8_string: {d} -> {d}", .{ utf8_string_cookie.sequence, utf8_string.id });

    const title = "Title!";

    cr.changeProperty(
        connection,
        xcb.PROP_MODE.replace,
        window,
        .{ .id = xcb.ATOM.wm_name },
        .{ .id = xcb.ATOM.string },
        8,
        title.len,
        @ptrCast(title.ptr),
    );

    cr.changeProperty(
        connection,
        xcb.PROP_MODE.replace,
        window,
        net_wm_name,
        utf8_string,
        8,
        title.len,
        @ptrCast(title.ptr),
    );

    _ = bs.flush(connection);

    while (true) {
        const event = bs.waitForEvent(connection) orelse break;

        switch (event.response_type & 0x7f) {
            xcb.Expose.opcode => {
                // redraw here
            },
            xcb.ClientMessage.opcode => {
                // window close handling
                break;
            },
            xcb.KeyPress.opcode => {
                std.log.info("keypress!", .{});
            },
            xcb.KeyRelease.opcode => {
                std.log.info("key release!", .{});
            },
            else => {},
        }
    }
}
