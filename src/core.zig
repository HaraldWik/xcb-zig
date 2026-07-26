pub const Xid = packed struct(u32) {
    id: u32,

    pub const none: Xid = .{ .id = 0 };
};
