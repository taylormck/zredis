const std = @import("std");

pub const Value = union(enum) {
    SimpleString: []const u8,
    Error: []const u8,
    Integer: i64,
    BulkString: []u8,
    Array: []Value,

    const Self = @This();

    pub fn simple_string(data: []const u8) !Value {
        return .{ .SimpleString = data };
    }

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        self.write(writer);
    }

    pub fn write(self: Self, writer: anytype) !void {
        switch (self) {
            .SimpleString => |s| try writer.print("+{s}\r\n", .{s}),
            else => {},
        }
    }
};
