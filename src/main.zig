const std = @import("std");
const net = std.net;
const RESP = @import("./resp.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const address = try net.Address.resolveIp("127.0.0.1", 6379);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    try stdout.print("awaiting, connection\n", .{});

    while (true) {
        const connection = try listener.accept();
        try stdout.print("accepted new connection\n", .{});

        // NOTE: for now, we just spawn a new thread. However, in the future,
        // we should consider creating either a thread pool or an event loop.
        const thread = try std.Thread.spawn(.{}, handle_connection, .{connection});
        thread.detach();
    }
}

const ConnectionError = error{
    ArgsNotCommandArray,
    ArgNotBulkString,
    UnsupportedCommand,
};

pub fn handle_connection(connection: std.net.Server.Connection) !void {
    const stdout = std.io.getStdOut().writer();
    const reader = connection.stream.reader();
    const writer = connection.stream.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;
    var bytes_read = try reader.read(&buffer);

    while (bytes_read > 0) {
        var stream = std.io.fixedBufferStream(buffer[0..bytes_read]);

        const command_content = try RESP.Value.read(allocator, stream.reader());
        const command = try Command.from_resp_value(allocator, command_content, reader);
        try command.execute(writer);

        bytes_read = try reader.read(&buffer);
    }
    connection.stream.close();
    try stdout.print("connection closed\n", .{});
}

pub const Command = union(enum) {
    Ping: []const u8,
    Echo: []const u8,

    const Self = @This();
    pub const Error = error{
        ParseError,
    };

    pub fn from_resp_value(allocator: std.mem.Allocator, input: RESP.Value, _: anytype) !Self {
        const command_array = switch (input) {
            .Array => |arr| arr,
            else => {
                return ConnectionError.ArgsNotCommandArray;
            },
        };

        const command = switch (command_array[0]) {
            .BulkString => |s| s,
            else => return ConnectionError.ArgNotBulkString,
        };

        const command_upper = try std.ascii.allocUpperString(
            allocator,
            command,
        );

        if (std.mem.eql(u8, command_upper, "PING")) {
            const ping_text = switch (command_array.len) {
                1 => "PONG",
                else => switch (command_array[1]) {
                    .BulkString => |s| s,
                    else => {
                        return ConnectionError.ArgNotBulkString;
                    },
                },
            };

            return .{ .Ping = ping_text };
        }

        return Error.ParseError;
    }

    pub fn execute(self: *const Self, writer: anytype) !void {
        const response = switch (self.*) {
            .Ping => |str| RESP.Value.simple_string(str),
            else => return ConnectionError.UnsupportedCommand,
        };

        try response.write(writer);
    }
};

test {
    std.testing.refAllDecls(@This());
}
