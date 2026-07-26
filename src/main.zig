const builtin = @import("builtin");

const std = @import("std");
const xml = @import("xml.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;

    var output_opt: ?[:0]const u8 = null;
    var files: std.ArrayList([:0]const u8) = .empty;
    defer files.deinit(gpa);

    var args = try init.minimal.args.iterateAllocator(arena);
    defer args.deinit();
    _ = args.skip();

    const args_count: ?usize = switch (builtin.os.tag) {
        .windows => null,
        .wasi => if (builtin.link_libc) args.inner.remaining.len else null,
        else => args.inner.remaining.len,
    };
    if (args_count) |count| try files.ensureTotalCapacityPrecise(gpa, count);

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-o")) {
            output_opt = args.next();
        } else if (std.mem.endsWith(u8, arg, ".xml")) {
            if (args_count == null)
                try files.append(gpa, arg)
            else
                files.appendAssumeCapacity(arg);
        }
    }

    const protocols = try gpa.alloc(Protocol, files.items.len);
    defer gpa.free(protocols);

    for (files.items, protocols) |file_path, *protocol| {
        const file = try std.Io.Dir.openFileAbsolute(io, file_path, .{});
        defer file.close(io);

        var file_reader = file.reader(io, &.{});
        const source = try file_reader.interface.allocRemaining(arena, .unlimited);

        protocol.* = try .parse(gpa, source);
    }
    defer for (protocols) |*protocol| protocol.deinit(gpa);

    var output_allocating: std.Io.Writer.Allocating = .init(gpa);
    defer output_allocating.deinit();
    const output = &output_allocating.writer;

    try output.writeAll(@embedFile("core.zig"));

    for (protocols) |protocol| try protocol.emit(output);

    const output_file = try std.Io.Dir.createFileAbsolute(io, output_opt orelse return error.NoOutput, .{});
    defer output_file.close(io);

    try output_file.writeStreamingAll(io, output.buffered());
}

pub const Protocol = struct {
    xids: std.ArrayList(Xid) = .empty,

    pub const Xid = struct {
        name: []const u8,
    };

    pub const Struct = struct {
        fields: []const u8,
    };

    pub const Decleration = union(enum) {
        xidtype: Xid,

        pub const Tag = std.meta.Tag(Decleration);
    };

    pub fn parse(gpa: std.mem.Allocator, document: []const u8) !Protocol {
        var parser: xml.Parser = .init(document);

        var xids: std.ArrayList(Xid) = .empty;

        var decleration: ?Decleration = null;
        while (parser.next()) |content| switch (content) {
            .open_tag => |tag_name| {
                const tag = std.meta.stringToEnum(Decleration.Tag, tag_name) orelse continue;
                switch (tag) {
                    inline else => |comptime_tag| {
                        decleration = @unionInit(Decleration, @tagName(comptime_tag), undefined);
                    },
                }
            },
            .close_tag => {
                if (decleration) |decl| switch (decl) {
                    .xidtype => |xid| try xids.append(gpa, xid),
                };
                decleration = null;
            },
            .attribute => |attribute| if (decleration) |decl| switch (std.meta.activeTag(decl)) {
                inline else => |tag| {
                    const T = @FieldType(Decleration, @tagName(tag));

                    inline for (std.meta.fields(T)) |field| {
                        if (std.mem.eql(u8, attribute.name, field.name)) {
                            @field(@field(decleration.?, @tagName(tag)), field.name) = attribute.raw_value;
                        }
                    }
                },
                // .xidtype => {
                // std.debug.assert(attribute.name)
                // decl.?.xidtype.name
                // },
            },
            .comment => {},
            .processing_instruction => {},
            .character_data => {},
        };

        return .{
            .xids = xids,
        };
    }

    pub fn deinit(self: *Protocol, gpa: std.mem.Allocator) void {
        self.xids.deinit(gpa);
        self.* = undefined;
    }

    pub fn emit(self: Protocol, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.xids.items) |xid| {
            try writer.print("pub const {f} = Xid;\n", .{titleCase(xid.name)});
        }
    }
};

const Case = enum {
    title,
    camel,
    snake,
};

fn formatCaseImpl(comptime case: Case, comptime trim: bool) type {
    return struct {
        pub fn f(bytes: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            const str = if (trim) trimPrefix(bytes) else bytes;

            if ((case == .camel or case == .snake) and std.zig.Token.getKeyword(str) != null) {
                try writer.print("@\"{s}\"", .{str});
                return;
            }

            switch (case) {
                .snake => {
                    for (str) |c| {
                        try writer.writeByte(std.ascii.toLower(c));
                    }
                },
                .camel, .title => {
                    var upper = case == .title;

                    for (str) |c| {
                        if (c == '_') {
                            upper = true;
                            continue;
                        }

                        try writer.writeByte(if (upper)
                            std.ascii.toUpper(c)
                        else
                            std.ascii.toLower(c));

                        upper = false;
                    }
                },
            }
        }
    };
}

fn trimPrefix(s: []const u8) []const u8 {
    return s[std.mem.indexOfScalar(u8, s, '_').? + 1 ..];
}

fn titleCase(bytes: []const u8) std.fmt.Alt([]const u8, formatCaseImpl(.title, false).f) {
    return .{ .data = bytes };
}

fn titleCaseTrim(bytes: []const u8) std.fmt.Alt([]const u8, formatCaseImpl(.title, true).f) {
    return .{ .data = bytes };
}

fn camelCase(bytes: []const u8) std.fmt.Alt([]const u8, formatCaseImpl(.camel, false).f) {
    return .{ .data = bytes };
}

fn camelCaseTrim(bytes: []const u8) std.fmt.Alt([]const u8, formatCaseImpl(.camel, true).f) {
    return .{ .data = bytes };
}

fn snakeCase(bytes: []const u8) std.fmt.Alt([]const u8, formatCaseImpl(.snake, false).f) {
    return .{ .data = bytes };
}

fn snakeCaseTrim(bytes: []const u8) std.fmt.Alt([]const u8, formatCaseImpl(.snake, true).f) {
    return .{ .data = bytes };
}
