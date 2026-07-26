const std = @import("std");
const xcb = @import("xcb");

pub fn main() !void {
    const connection = try xcb.connect(null, null) orelse return error.Connect;
    defer xcb.disconnect(connection);
    if (xcb.connectionHasError(connection) != 0) return error.Connect;

    const setup = xcb.getSetup(connection);
    const screen = xcb.setupRootsIterator(setup).data.?.*;
}
