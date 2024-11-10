const std = @import("std");
const RESP = @import("./resp.zig");

pub const Command = union(enum) {
    Ping: []const u8,
    Echo: []const u8,
    Set: [2][]const u8,
    Get: []const u8,

    const Self = @This();
    const Error = error{
        ArgsNotCommandArray,
        ArgNotBulkString,
        UnsupportedCommand,
    };

    pub fn from_resp_value(allocator: std.mem.Allocator, input: RESP.Value, _: anytype) !Self {
        const command_array = switch (input) {
            .Array => |arr| arr,
            else => {
                return Error.ArgsNotCommandArray;
            },
        };

        const command = switch (command_array[0]) {
            .BulkString => |s| s,
            else => return Error.ArgNotBulkString,
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
                        return Error.ArgNotBulkString;
                    },
                },
            };

            return .{ .Ping = ping_text };
        }

        if (std.mem.eql(u8, command_upper, "ECHO")) {
            const echo_text =
                switch (command_array[1]) {
                .BulkString => |s| s,
                else => {
                    return Error.ArgNotBulkString;
                },
            };

            return .{ .Echo = echo_text };
        }

        return Error.UnsupportedCommand;
    }

    pub fn execute(self: *const Self, writer: anytype) !void {
        const response = switch (self.*) {
            .Ping => |str| RESP.Value.bulk_string(str),
            .Echo => |str| RESP.Value.bulk_string(str),
            else => return Error.UnsupportedCommand,
        };

        try response.write(writer);
    }
};
