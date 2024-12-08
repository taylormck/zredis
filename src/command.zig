const std = @import("std");
const RESP = @import("./resp.zig");
const data = @import("./data.zig");
const cli_args = @import("./cli-args.zig");

const SetData = struct {
    key: []const u8,
    value: []const u8,
    expiry: ?i64,
};

pub const Command = union(enum) {
    Ping: []const u8,
    Echo: []const u8,
    Set: SetData,
    Get: []const u8,
    Config: [][]const u8,

    const Self = @This();
    const Error = error{
        ArgsNotCommandArray,
        ArgNotBulkString,
        UnsupportedCommand,
        InsufficientArguments,
        ArgNotInteger,
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
        if (std.ascii.eqlIgnoreCase(command, "PING")) {
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

        if (std.ascii.eqlIgnoreCase(command, "ECHO")) {
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

        if (std.ascii.eqlIgnoreCase(command, "SET")) {
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

            const expiry = blk: {
                if (command_array.len < 5) {
                    break :blk null;
                }

                const extra_arg = switch (command_array[3]) {
                    .BulkString => |s| s,
                    else => {
                        return Error.ArgNotBulkString;
                    },
                };

                if (!std.ascii.eqlIgnoreCase(extra_arg, "PX")) {
                    break :blk null;
                }

                break :blk switch (command_array[4]) {
                    .BulkString => |s| try std.fmt.parseInt(i64, s, 10),
                    else => {
                        return Error.ArgNotBulkString;
                    },
                };
            };

            return .{ .Set = .{
                .key = key,
                .value = value,
                .expiry = expiry,
            } };
        }

        if (std.ascii.eqlIgnoreCase(command, "GET")) {
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

        if (std.ascii.eqlIgnoreCase(command, "CONFIG")) {
            const subcommand = switch (command_array.len) {
                1 => "",
                else => switch (command_array[1]) {
                    .BulkString => |s| s,
                    else => {
                        return Error.ArgNotBulkString;
                    },
                },
            };

            var command_args = std.ArrayList([]const u8).init(allocator);
            errdefer command_args.deinit();

            try command_args.append(subcommand);

            if (std.ascii.eqlIgnoreCase(subcommand, "get")) {
                // NOTE: assert command_array has another property
                const config_entry_name = switch (command_array[2]) {
                    .BulkString => |s| s,
                    else => {
                        return Error.ArgNotBulkString;
                    },
                };

                try command_args.append(config_entry_name);
            }

            return .{ .Config = try command_args.toOwnedSlice() };
        }

        const stderr = std.io.getStdErr().writer();
        try stderr.print("Unsupported command: {s}\n", .{command});

        return Error.UnsupportedCommand;
    }

    pub fn execute(self: *const Self, writer: anytype, configuration: cli_args.Args) !void {
        const response = switch (self.*) {
            .Ping => |str| RESP.Value.bulk_string(str),
            .Echo => |str| RESP.Value.bulk_string(str),
            .Set => |set_data| blk: {
                try data.set(set_data.key, set_data.value, set_data.expiry);

                break :blk RESP.Value.simple_string("OK");
            },
            .Get => |key| data.get(key),
            .Config => |arr| blk: {
                if (std.ascii.eqlIgnoreCase("get", arr[0])) {
                    var response_values: [2]RESP.Value = .{
                        RESP.Value.bulk_string(arr[1]),
                        RESP.Value.null_bulk_string(),
                    };

                    if (std.ascii.eqlIgnoreCase("dir", arr[1])) {
                        if (configuration.directory) |dir| {
                            response_values[1] = RESP.Value.bulk_string(dir);
                        }
                    }

                    if (std.ascii.eqlIgnoreCase("dbfilename", arr[1])) {
                        if (configuration.dbfilename) |dbfilename| {
                            response_values[1] = RESP.Value.bulk_string(dbfilename);
                        }
                    }

                    break :blk RESP.Value.array(&response_values);
                }

                break :blk RESP.Value.simple_string("OK");
            },
        };

        try response.write(writer);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Config => |arr| {
                allocator.free(arr);
            },
            else => {},
        }
    }
};
