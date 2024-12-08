const std = @import("std");
const net = std.net;
const RESP = @import("./resp.zig");
const Command = @import("./command.zig").Command;
const data = @import("./data.zig");
const cli_args = @import("./cli-args.zig");
const rdb = @import("./rdb.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const stdout = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const process_config = try cli_args.process_args(args);

    if (process_config.directory) |dir| {
        if (process_config.dbfilename) |dbfilename| {
            try read_persistence_data(allocator, dir, dbfilename);
        }
    }

    const address = try net.Address.resolveIp("127.0.0.1", 6379);

    var listener = try address.listen(.{
        .reuse_address = true,
    });

    defer listener.deinit();

    data.initialize_data(allocator);
    defer data.deinit_data();

    try stdout.print("awaiting, connection\n", .{});

    while (true) {
        const connection = try listener.accept();
        try stdout.print("accepted new connection\n", .{});

        // NOTE: for now, we just spawn a new thread. However, in the future,
        // we should consider creating either a thread pool or an event loop.
        const thread = try std.Thread.spawn(.{}, handle_connection, .{ connection, process_config });
        thread.detach();
    }
}

pub fn handle_connection(connection: std.net.Server.Connection, configuration: cli_args.Args) !void {
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
        try command.execute(writer, configuration);

        bytes_read = try reader.read(&buffer);
    }
    connection.stream.close();
    try stdout.print("connection closed\n", .{});
}

pub fn read_persistence_data(allocator: std.mem.Allocator, dir: []const u8, dbfilename: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, dbfilename });
    defer allocator.free(path);
    try stdout.print("Loading persitence data from: {s}\n", .{path});

    const rdb_file = std.fs.openFileAbsolute(path, .{ .mode = .read_write }) catch return;

    var header_buffer: [9]u8 = undefined;
    _ = try rdb_file.reader().readAll(&header_buffer);

    const is_valid_header = rdb.check_header_section(&header_buffer) catch return;
    if (!is_valid_header) {
        return;
    }

    // TODO: read data from db
}

test {
    std.testing.refAllDecls(@This());
}
