const std = @import("std");

// The maximum size Redis allows for bulk strings is 512 MB.
const BULK_STRING_MAX_LENGTH = 512 * 1024 * 1024;

pub const Value = union(enum) {
    SimpleString: []const u8,
    SimpleError: []const u8,
    Integer: i64,
    BulkString: []const u8,
    Array: []const Value,

    const Self = @This();

    const Error = error{
        ParseError,
    };

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

    pub fn read(allocator: std.mem.Allocator, reader: anytype) !Self {
        const type_token = try next(reader);

        return switch (type_token) {
            '+' => {
                var content = std.ArrayList(u8).init(allocator);
                errdefer content.deinit();

                try reader.streamUntilDelimiter(content.writer(), '\r', null);
                try consume(reader, '\n');

                return Self.simple_string(try content.toOwnedSlice());
            },
            '$' => {
                var length_buffer = std.ArrayList(u8).init(allocator);
                errdefer length_buffer.deinit();

                try reader.streamUntilDelimiter(length_buffer.writer(), '\r', null);
                try consume(reader, '\n');

                const length = try std.fmt.parseInt(usize, length_buffer.items, 10);

                var content_buffer = std.ArrayList(u8).init(allocator);
                errdefer content_buffer.deinit();
                try content_buffer.ensureTotalCapacityPrecise(length);

                const content_bytes_read = try reader.read(content_buffer.items);

                if (content_bytes_read != length) {
                    return Self.Error.ParseError;
                }

                try consume(reader, '\r');
                try consume(reader, '\n');

                return Self.bulk_string(try content_buffer.toOwnedSlice());
            },
            // '*' => {},
            // TODO: replace with actual error handling
            else => Self.simple_string("oops"),
        };
    }

    // TODO: implement deninit
    pub fn deinit() void {}
};

const ReaderError = error{
    UnexpectedByte,
};

fn next(reader: anytype) !u8 {
    return try reader.readByte();
}

fn consume(reader: anytype, expected_byte: u8) !void {
    const next_char = try next(reader);

    if (next_char != expected_byte) {
        return ReaderError.UnexpectedByte;
    }
}

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

test "read a simple string" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;

    var content = std.ArrayList(u8).init(test_allocator);
    defer content.deinit();
    const bytes_written = try content.writer().write("+foo\r\n");

    try expect(bytes_written == 6);

    var stream = std.io.fixedBufferStream(content.items);

    const result = try Value.read(test_allocator, stream.reader());

    switch (result) {
        .SimpleString => |s| try expect(std.mem.eql(u8, s, "foo")),
        else => try expect(false),
    }
}
