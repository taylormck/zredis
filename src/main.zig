const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const address = try net.Address.resolveIp("127.0.0.1", 6379);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    try stdout.print("awaiting connection\n", .{});

    while (true) {
        const connection = try listener.accept();

        try stdout.print("accepted new connection\n", .{});

        const reader = connection.stream.reader();
        const writer = connection.stream.writer();
        var buffer: [1024]u8 = undefined;

        while (try reader.read(&buffer) > 0) {
            try writer.writeAll("+PONG\r\n");
        }

        connection.stream.close();
    }
}
