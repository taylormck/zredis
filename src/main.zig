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

        const buffer = [_]u8{};
        _ = try connection.stream.read(&buffer);

        const pong = "+PONG\r\n";
        _ = try connection.stream.write(pong);

        connection.stream.close();
    }
}
