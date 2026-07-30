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
        } else if (std.mem.endsWith(u8, arg, ".zon")) {
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
        const source = try file_reader.interface.allocRemainingAlignedSentinel(arena, .unlimited, .of(u8), 0);

        protocol.* = try .parse(arena, source);
    }

    var output_allocating: std.Io.Writer.Allocating = .init(gpa);
    defer output_allocating.deinit();
    const output = &output_allocating.writer;

    try output.writeAll(@embedFile("core.zig"));

    for (protocols) |protocol| try protocol.emit(output);

    try output.writeByte(0);

    const output_path = output_opt orelse return error.NoOutput;
    const output_file = try std.Io.Dir.createFileAbsolute(io, output_path, .{});
    defer output_file.close(io);

    var tree = try std.zig.Ast.parse(gpa, output.buffer[0 .. output.end - 1 :0], .zig);
    defer tree.deinit(gpa);

    if (tree.errors.len != 0) {
        try output_file.writeStreamingAll(io, output.buffered());
        return;
        // try std.zig.printAstErrorsToStderr(gpa, io, tree, "generated", .auto);
        // return error.ParseError;
    }

    var out_buf: [4096]u8 = undefined;
    var out_writer = output_file.writer(io, &out_buf);

    try tree.render(gpa, &out_writer.interface, .{});

    try out_writer.flush();
}

pub const Protocol = struct {
    /// e.g "core" or "big_request"
    name: []const u8,

    xids: []const Xid,
    xidunions: []const XidUnion,
    typedefs: []const Typedef,

    enums: []const Enum,
    bitmasks: []const Bitmask,

    structs: []const Struct,
    unions: []const Union,

    requests: []const Request,
    replies: []const Struct,

    events: []const Event,
    errors: []const Struct,

    pub const Xid = struct {
        name: []const u8,
    };

    pub const XidUnion = struct {
        name: []const u8,
        types: []const []const u8,
    };

    pub const Typedef = struct {
        old: []const u8,
        new: []const u8,
    };

    pub const Enum = struct {
        name: []const u8,
        fields: []const EnumField,
    };

    pub const Bitmask = struct {
        name: []const u8,
        fields: []const EnumField,
    };

    pub const EnumField = struct {
        name: []const u8,
        value: u64,
    };

    pub const Struct = struct {
        name: []const u8,
        fields: []const Field,
    };

    pub const Union = struct {
        name: []const u8,
        fields: []const Field,
    };

    pub const Field = struct {
        name: ?[]const u8 = null,
        type: ?[]const u8 = null,

        // Underlying storage type if enum can represent multiple types.
        // Example:
        // .{
        //     .name = "backing_stores",
        //     .type = "BackingStore",
        //     .type_info = "u8",
        // }
        type_info: ?[]const u8 = null,

        @"enum": ?[]const u8 = null,

        list: bool = false,
        fieldref: ?[]const u8 = null,

        pad: ?u32 = null,
        alignment: ?u32 = null,
    };

    pub const Request = struct {
        name: []const u8,
        params: []const Field,
        returns: ?[]const u8 = null,
    };

    pub const Event = struct {
        name: []const u8,
        number: u8,
        fields: []const Field,
    };

    pub fn parse(arena: std.mem.Allocator, source: [:0]const u8) error{ OutOfMemory, ParseZon }!Protocol {
        var diag: std.zon.parse.Diagnostics = .{};
        defer diag.deinit(arena);

        return std.zon.parse.fromSliceAlloc(
            Protocol,
            arena,
            source,
            &diag,
            .{},
        ) catch {
            var it = diag.iterateErrors();

            while (it.next()) |err| {
                std.log.err("{f}", .{
                    err.fmtMessage(&diag),
                });
            }

            return error.ParseZon;
        };
    }

    pub fn emit(self: Protocol, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeByte('\n');
        for (self.xids) |xid| {
            try w.print("pub const {f} = Xid;\n", .{typeCase(xid.name)});
        }

        try w.writeByte('\n');
        for (self.xidunions) |xidunion| {
            try w.print("pub const {f} = extern union {{\n", .{typeCase(xidunion.name)});
            for (xidunion.types) |t| {
                try w.print("{f}: {f},\n", .{ snakeCase(t), typeCase(t) });
            }
            try w.writeAll("};\n");
        }

        try w.writeByte('\n');
        for (self.typedefs) |typedef| {
            try w.print("pub const {f} = {f};\n", .{ typeCase(typedef.new), typeCase(typedef.old) });
        }

        try w.writeByte('\n');
        for (self.enums) |e| {
            try w.print("pub const {f} = struct {{\n", .{screamingSnakeCase(e.name)});
            for (e.fields) |field| {
                try w.print("pub const {f} = {d};\n", .{ snakeCase(field.name), field.value });
            }
            try w.writeAll("};\n");
        }

        try w.writeByte('\n');
        for (self.bitmasks) |bitmask| {
            try w.print("pub const {f} = struct {{\n", .{screamingSnakeCase(bitmask.name)});
            for (bitmask.fields) |field| {
                try w.print("pub const {f} = {d};\n", .{ snakeCase(field.name), field.value });
            }
            try w.writeAll("};\n");
        }

        try w.writeByte('\n');
        for (self.structs) |s| try emitStruct(s, w);

        try w.writeByte('\n');
        for (self.unions) |u| {
            try w.print("pub const {f} = extern union {{\n", .{typeCase(u.name)});
            for (u.fields) |field| {
                try w.print("{f}: {f},\n", .{ snakeCase(field.name.?), typeCase(field.type.?) });
            }
            try w.writeAll("};\n");
        }

        try w.writeByte('\n');
        for (self.replies) |reply| try emitStruct(reply, w);
        try w.writeByte('\n');
        for (self.events) |event| {
            var pad_index: usize = 0;
            try w.print("pub const {f} = extern struct {{\n", .{typeCase(event.name)});
            for (event.fields) |field| {
                const pad = field.pad orelse field.alignment;
                if (pad) |bytes| {
                    try w.print("pad{d}: [{d}]u8,\n", .{ pad_index, bytes });
                    pad_index += 1;
                    continue;
                }

                const name = field.name orelse continue;
                const t = field.type orelse continue;

                try w.print("{f}: {s}{f},\n", .{ snakeCase(name), if (field.list) "[*]const " else "", typeCase(t) });
            }
            try w.print("pub const opcode = {d};", .{event.number});
            try w.writeAll("};\n");
        }
        try w.writeByte('\n');
        for (self.errors) |err| {
            var pad_index: usize = 0;
            try w.print("pub const {f}Error = extern struct {{\n", .{typeCase(err.name)});
            for (err.fields) |field| {
                const pad = field.pad orelse field.alignment;
                if (pad) |bytes| {
                    try w.print("pad{d}: [{d}]u8,\n", .{ pad_index, bytes });
                    pad_index += 1;
                    continue;
                }

                const name = field.name orelse continue;
                const t = field.type orelse continue;

                try w.print("{f}: {s}{f},\n", .{ snakeCase(name), if (field.list) "[*]const " else "", typeCase(t) });
            }
            try w.writeAll("};\n");
        }

        try emitRequests(self.requests, w, self.name);
    }

    fn emitStruct(s: Struct, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var pad_index: usize = 0;
        try w.print("pub const {f} = extern struct {{\n", .{typeCase(s.name)});
        for (s.fields) |field| {
            const pad = field.pad orelse field.alignment;
            if (pad) |bytes| {
                try w.print("pad{d}: [{d}]u8,\n", .{ pad_index, bytes });
                pad_index += 1;
                continue;
            }

            const name = field.name orelse continue;
            const t = field.type orelse continue;

            try w.print("{f}: {s}{f},\n", .{ snakeCase(name), if (field.list) "[*]const " else "", typeCase(t) });
        }
        try w.writeAll("};\n");
    }

    fn emitRequests(requests: []const Request, w: *std.Io.Writer, protocol_name: []const u8) std.Io.Writer.Error!void {
        // proc table
        try w.print("pub const {f}Dispatch = struct {{\n", .{titleCase(protocol_name)});
        for (requests) |request| {
            try w.print("   xcb_{s}: ?*const fn (connection: Connection", .{request.name});
            if (request.params.len > 0) try w.writeAll(", ");
            var first = true;
            for (request.params) |param| {
                if (param.pad != null or param.alignment != null) continue;

                if (!first) try w.writeAll(",\n");

                try w.print("{f}: {s}{f}", .{
                    snakeCase(param.name.?),
                    if (param.list) "[*]const " else "",
                    typeCase(param.type.?),
                });

                first = false;
            }
            try w.writeAll(") callconv(.c) ");
            if (request.returns) |returns| {
                try w.print("Cookie({f}) = null,\n", .{typeCase(returns)});

                try w.print("   xcb_{s}_reply: ?*const fn (connection: Connection, cookie: Cookie({f}), err: ?*?*GenericError) callconv(.c) *{f} = null,\n", .{ request.name, typeCase(returns), typeCase(returns) });
            } else {
                try w.writeAll("void = null,\n");
            }
        }
        try w.writeAll("};\n");

        // dispatch and wrapper
        try w.print(
            \\pub const {f}Wrapper = {f}WrapperWithCustomDispatch({f}Dispatch);
            \\pub fn {f}WrapperWithCustomDispatch(DispatchType: type) type {{
            \\    return struct {{
            \\        const Self = @This();
            \\        pub const Dispatch = DispatchType;
            \\
            \\        dispatch: Dispatch,
            \\
            \\        pub fn load(dynlib: *std.DynLib) Self {{
            \\            var self: Self = .{{ .dispatch = .{{}} }};
            \\            inline for (std.meta.fields(Dispatch)) |field| {{
            \\                if (dynlib.lookup(field.type, field.name)) |cmd_ptr| {{
            \\                    @field(self.dispatch, field.name) = @ptrCast(cmd_ptr);
            \\                }}
            \\            }}
            \\            return self;
            \\        }}
        , .{ titleCase(protocol_name), titleCase(protocol_name), titleCase(protocol_name), titleCase(protocol_name) });

        for (requests) |request| {
            try w.print("pub fn {f}(", .{camelCase(request.name)});
            try w.print("self: Self, connection: Connection", .{});
            if (request.params.len > 0) try w.writeAll(", ");
            for (request.params, 0..) |param, i| {
                if (param.pad != null or param.alignment != null) continue;
                const is_last = i == request.params.len - 1;

                try w.print("{f}: {s}{f}", .{ snakeCase(param.name.?), if (param.list) "[*]const " else "", typeCase(param.type.?) });

                if (!is_last) try w.writeAll(",");
            }
            try w.writeAll(") ");
            if (request.returns) |returns|
                try w.print("Cookie({f}) {{\nreturn ", .{typeCase(returns)})
            else
                try w.writeAll("void {\n");

            try w.print("self.dispatch.xcb_{s}.?(", .{request.name});
            try w.print("connection", .{});
            if (request.params.len > 0) try w.writeAll(", ");
            var first = true;
            for (request.params) |param| {
                if (param.pad != null or param.alignment != null) continue;

                if (!first) try w.writeAll(",");

                try w.print("{f}", .{snakeCase(param.name.?)});

                first = false;
            }
            try w.writeAll(");\n}\n");

            const returns = request.returns orelse continue;

            try w.print(
                \\pub fn {f}Reply(self: Self, connection: Connection, cookie: Cookie({f}), err: ?*?*GenericError) *{f} {{
                \\    return self.dispatch.xcb_{s}_reply.?(connection, cookie, err);
                \\}}
                \\
            ,
                .{ camelCase(request.name), typeCase(returns), typeCase(returns), request.name },
            );
        }

        try w.writeAll("    };\n}\n");
    }
};

const Case = enum {
    title,
    camel,
    snake,
    screaming_snake,
    type,
};

fn formatCaseImpl(comptime case: Case, comptime trim: bool) type {
    return struct {
        pub fn f(bytes: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            if (bytes.len == 0) return writer.writeAll("unknown");
            const str = if (trim) trimPrefix(bytes) else bytes;

            if (case == .snake and std.mem.eql(u8, str, "type") or std.zig.Token.getKeyword(str) != null or std.ascii.isDigit(str[0])) {
                try writer.print("@\"{s}\"", .{str});
                return;
            }

            switch (case) {
                .snake => {
                    var prev: ?u8 = null;

                    for (str, 0..) |c, i| {
                        if (std.ascii.isUpper(c)) {
                            const needs_separator =
                                i != 0 and
                                prev != '_' and
                                (prev != null and !std.ascii.isUpper(prev.?));

                            if (needs_separator) {
                                try writer.writeByte('_');
                            }

                            try writer.writeByte(std.ascii.toLower(c));
                        } else {
                            try writer.writeByte(c);
                        }

                        prev = c;
                    }
                },
                .screaming_snake => {
                    var prev: ?u8 = null;

                    for (str, 0..) |c, i| {
                        if (std.ascii.isUpper(c)) {
                            const needs_separator =
                                i != 0 and
                                prev != '_' and
                                (prev != null and !std.ascii.isUpper(prev.?));

                            if (needs_separator) {
                                try writer.writeByte('_');
                            }

                            try writer.writeByte(std.ascii.toUpper(c));
                        } else {
                            try writer.writeByte(std.ascii.toUpper(c));
                        }

                        prev = c;
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
                .type => {
                    const is_builtin = builtin: {
                        if (std.mem.eql(u8, str, "void") or std.mem.eql(u8, str, "bool")) break :builtin true;

                        if (str.len < 2)
                            break :builtin false;

                        if (str[0] != 'u' and str[0] != 'i')
                            break :builtin false;

                        for (str[1..]) |c| {
                            if (!std.ascii.isDigit(c))
                                break :builtin false;
                        }

                        break :builtin true;
                    };

                    if (is_builtin) {
                        try writer.writeAll(str);
                        return;
                    }

                    var upper = true;

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

fn screamingSnakeCase(bytes: []const u8) std.fmt.Alt([]const u8, formatCaseImpl(.screaming_snake, false).f) {
    return .{ .data = bytes };
}

fn screamingSnakeCaseTrim(bytes: []const u8) std.fmt.Alt([]const u8, formatCaseImpl(.screaming_snake, true).f) {
    return .{ .data = bytes };
}

fn typeCase(bytes: []const u8) std.fmt.Alt([]const u8, formatCaseImpl(.type, false).f) {
    return .{ .data = bytes };
}

fn typeCaseTrim(bytes: []const u8) std.fmt.Alt([]const u8, formatCaseImpl(.type, true).f) {
    return .{ .data = bytes };
}
