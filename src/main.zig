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

pub fn handle_connection(connection: std.net.Server.Connection) !void {
    const reader = connection.stream.reader();
    const writer = connection.stream.writer();
    var buffer: [1024]u8 = undefined;

    var n = try reader.read(&buffer);

    while (n > 0) {
        try handle_command(writer, buffer[0..n]);

        n = try reader.read(&buffer);
    }

    connection.stream.close();
}

pub fn handle_command(writer: anytype, buffer: []u8) !void {
    const command = try Command.from_string(buffer);

    const response = switch (command) {
        .Ping => RESP.Value.simple_string("PONG"),
    };

    try response.write(writer);
}

pub const Command = enum {
    Ping,

    const Self = @This();
    pub const Error = error{
        ParseError,
    };

    pub fn from_string(s: []u8) !Self {
        // NOTE: I wonder if this is wise.
        // We're copying data into the string while we read from it.
        // In theory, we're always reading ahead, so it should be safe,
        // but if there are issues, this would be a place to be suspicious of.
        const s_upper = std.ascii.upperString(s, s);

        if (std.mem.eql(u8, s_upper, "PING")) {
            return .Ping;
        }

        return Error.ParseError;
    }
};

test {
    std.testing.refAllDecls(@This());
}
