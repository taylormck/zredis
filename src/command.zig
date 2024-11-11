const std = @import("std");
const RESP = @import("./resp.zig");
const data = @import("./data.zig");

pub const Command = union(enum) {
    Ping: []const u8,
    Echo: []const u8,
    Set: [2][]const u8,
    Get: []const u8,
    Config: []const u8,

    const Self = @This();
    const Error = error{
        ArgsNotCommandArray,
        ArgNotBulkString,
        UnsupportedCommand,
        InsufficientArguments,
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
            if (command_array.len < 2) {
                return Error.InsufficientArguments;
            }

            const echo_text =
                switch (command_array[1]) {
                .BulkString => |s| s,
                else => {
                    return Error.ArgNotBulkString;
                },
            };

            return .{ .Echo = echo_text };
        }

        if (std.mem.eql(u8, command_upper, "SET")) {
            if (command_array.len < 3) {
                return Error.InsufficientArguments;
            }

            const key =
                switch (command_array[1]) {
                .BulkString => |s| s,
                else => {
                    return Error.ArgNotBulkString;
                },
            };

            const value = switch (command_array[2]) {
                .BulkString => |s| s,
                else => {
                    return Error.ArgNotBulkString;
                },
            };

            var args = try allocator.create([2][]const u8);
            errdefer allocator.destroy(args);
            args[0] = key;
            args[1] = value;

            return .{ .Set = args.* };
        }

        if (std.mem.eql(u8, command_upper, "GET")) {
            if (command_array.len < 2) {
                return Error.InsufficientArguments;
            }

            const key =
                switch (command_array[1]) {
                .BulkString => |s| s,
                else => {
                    return Error.ArgNotBulkString;
                },
            };

            return .{ .Get = key };
        }

        if (std.mem.eql(u8, command_upper, "CONFIG")) {
            const subcommand = switch (command_array.len) {
                1 => "",
                else => switch (command_array[1]) {
                    .BulkString => |s| s,
                    else => {
                        return Error.ArgNotBulkString;
                    },
                },
            };
            return .{ .Config = subcommand };
        }

        const stderr = std.io.getStdErr().writer();
        try stderr.print("Unsupported command: {s}\n", .{command});

        return Error.UnsupportedCommand;
    }

    pub fn execute(self: *const Self, writer: anytype) !void {
        const response = switch (self.*) {
            .Ping => |str| RESP.Value.bulk_string(str),
            .Echo => |str| RESP.Value.bulk_string(str),
            .Set => |args| blk: {
                const key = args[0];
                const value = args[1];
                try data.set(key, value);

                break :blk RESP.Value.simple_string("OK");
            },
            .Get => |key| data.get(key),
            .Config => RESP.Value.simple_string("OK"),
            // else => return Error.UnsupportedCommand,
        };

        try response.write(writer);
    }

    // pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    //     switch (self.*) {
    //         // TODO: deinit the data
    //     }
    // }
};
