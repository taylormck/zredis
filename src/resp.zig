const std = @import("std");

pub const Value = union(enum) {
    SimpleString: []const u8,
    SimpleError: []const u8,
    Integer: i64,
    BulkString: []const u8,
    Array: []const Value,

    const Self = @This();

    pub fn simple_string(data: []const u8) Value {
        return .{ .SimpleString = data };
    }

    pub fn simple_error(data: []const u8) Value {
        return .{ .SimpleError = data };
    }

    pub fn integer(data: i64) Value {
        return .{ .Integer = data };
    }

    pub fn bulk_string(data: []const u8) Value {
        return .{ .BulkString = data };
    }

    pub fn array(data: []const Value) Value {
        return .{ .Array = data };
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
            .SimpleError => |s| try writer.print("-{s}\r\n", .{s}),
            .Integer => |n| try writer.print(":{d}\r\n", .{n}),
            .BulkString => |s| try writer.print("${d}\r\n{s}\r\n", .{ s.len, s }),
            .Array => |values| {
                try writer.print("*{d}\r\n", .{values.len});

                for (values) |value| {
                    try value.write(writer);
                }
            },
        }
    }

    // TODO: implement deninit
    pub fn deinit() void {}
};

test "write a simple string" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const val = Value.simple_string("foo");

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, "+foo\r\n"));
}

test "write an empty simple string" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const val = Value.simple_string("");

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, "+\r\n"));
}

test "write a simple error" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const val = Value.simple_error("foo");

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, "-foo\r\n"));
}

test "write an empty error" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const val = Value.simple_error("");

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, "-\r\n"));
}

test "write an integer" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const val = Value.integer(42);

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, ":42\r\n"));
}

test "write a negative integer" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const val = Value.integer(-42);

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, ":-42\r\n"));
}

test "write a bulk string" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const val = Value.bulk_string("foo");

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, "$3\r\nfoo\r\n"));
}

test "write an empty bulk string" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const val = Value.bulk_string("");

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, "$0\r\n\r\n"));
}

test "write an empty array" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const values = [_]Value{};
    const val = Value.array(values[0..]);

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, "*0\r\n"));
}

test "write an array with a single element" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const values = [_]Value{Value.simple_string("foo")};
    const val = Value.array(values[0..]);

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, "*1\r\n+foo\r\n"));
}

test "write an array with a multiple elements" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const values = [_]Value{
        Value.simple_string("foo"),
        Value.simple_string("bar"),
        Value.simple_string("xyz"),
    };
    const val = Value.array(values[0..]);

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, "*3\r\n+foo\r\n+bar\r\n+xyz\r\n"));
}

test "write an array with mixed element types" {
    const ArrayList = std.ArrayList;
    const expect = std.testing.expect;

    const test_allocator = std.testing.allocator;
    var buffer = ArrayList(u8).init(test_allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    const values = [_]Value{
        Value.simple_string("foo"),
        Value.simple_error("bar"),
        Value.bulk_string("xyz"),
        Value.integer(42),
        Value.integer(-42),
    };
    const val = Value.array(values[0..]);

    try val.write(writer);

    try expect(std.mem.eql(u8, buffer.items, "*5\r\n+foo\r\n-bar\r\n$3\r\nxyz\r\n:42\r\n:-42\r\n"));
}
