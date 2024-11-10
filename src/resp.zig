const std = @import("std");

// The maximum size Redis allows for bulk strings is 512 MB.
const BULK_STRING_MAX_LENGTH = 512 * 1024 * 1024;

pub const Value = union(enum) {
    SimpleString: []const u8,
    SimpleError: []const u8,
    Integer: i64,
    BulkString: []const u8,
    Array: []Value,

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

    pub fn array(data: []Value) Value {
        return .{ .Array = data };
    }

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try self.write(writer);
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
            '-' => {
                var content = std.ArrayList(u8).init(allocator);
                errdefer content.deinit();

                try reader.streamUntilDelimiter(content.writer(), '\r', null);
                try consume(reader, '\n');

                return Self.simple_error(try content.toOwnedSlice());
            },
            '$' => {
                var length_buffer = std.ArrayList(u8).init(allocator);
                defer length_buffer.deinit();

                try reader.streamUntilDelimiter(length_buffer.writer(), '\r', null);
                try consume(reader, '\n');

                const length = try std.fmt.parseInt(usize, length_buffer.items, 10);

                var content_buffer = std.ArrayList(u8).init(allocator);
                errdefer content_buffer.deinit();
                try content_buffer.ensureTotalCapacity(length);

                try reader.streamUntilDelimiter(content_buffer.writer(), '\r', null);
                try consume(reader, '\n');

                return Self.bulk_string(try content_buffer.toOwnedSlice());
            },
            ':' => {
                var content = std.ArrayList(u8).init(allocator);
                defer content.deinit();

                try reader.streamUntilDelimiter(content.writer(), '\r', null);
                try consume(reader, '\n');

                const data = try std.fmt.parseInt(i64, content.items, 10);

                return Self.integer(data);
            },
            '*' => {
                var length_buffer = std.ArrayList(u8).init(allocator);
                defer length_buffer.deinit();

                try reader.streamUntilDelimiter(length_buffer.writer(), '\r', null);
                try consume(reader, '\n');

                const length = try std.fmt.parseInt(usize, length_buffer.items, 10);

                var content = std.ArrayList(Value).init(allocator);
                errdefer content.deinit();

                while (content.items.len < length) {
                    const value = try Value.read(allocator, reader);
                    try content.append(value);
                }

                return Self.array(try content.toOwnedSlice());
            },
            else => ReaderError.UnexpectedByte,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .SimpleString, .SimpleError, .BulkString => |arr| allocator.free(arr),
            .Array => |arr| {
                for (arr, 0..) |_, i| {
                    arr[i].deinit(allocator);
                }
                allocator.free(arr);
            },
            .Integer => {},
        }
    }
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

    var values = [_]Value{Value.simple_string("foo")};
    const val = Value.array(&values);

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

    var values = [_]Value{
        Value.simple_string("foo"),
        Value.simple_string("bar"),
        Value.simple_string("xyz"),
    };
    const val = Value.array(&values);

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
    var values = [_]Value{
        Value.simple_string("foo"),
        Value.simple_error("bar"),
        Value.bulk_string("xyz"),
        Value.integer(42),
        Value.integer(-42),
    };
    const val = Value.array(&values);

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

    var result = try Value.read(test_allocator, stream.reader());
    defer result.deinit(test_allocator);

    switch (result) {
        .SimpleString => |s| try expect(std.mem.eql(u8, s, "foo")),
        else => try expect(false),
    }
}

test "read a simple error" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;

    var content = std.ArrayList(u8).init(test_allocator);
    defer content.deinit();
    const bytes_written = try content.writer().write("-foo\r\n");

    try expect(bytes_written == 6);

    var stream = std.io.fixedBufferStream(content.items);

    var result = try Value.read(test_allocator, stream.reader());
    defer result.deinit(test_allocator);

    switch (result) {
        .SimpleError => |s| try expect(std.mem.eql(u8, s, "foo")),
        else => try expect(false),
    }
}

test "read an integer" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;

    var content = std.ArrayList(u8).init(test_allocator);
    defer content.deinit();
    const bytes_written = try content.writer().write(":42\r\n");

    try expect(bytes_written == 5);

    var stream = std.io.fixedBufferStream(content.items);

    var result = try Value.read(test_allocator, stream.reader());
    defer result.deinit(test_allocator);

    switch (result) {
        .Integer => |n| try expect(n == 42),
        else => try expect(false),
    }
}

test "read a negative integer" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;

    var content = std.ArrayList(u8).init(test_allocator);
    defer content.deinit();
    const bytes_written = try content.writer().write(":-42\r\n");

    try expect(bytes_written == 6);

    var stream = std.io.fixedBufferStream(content.items);

    var result = try Value.read(test_allocator, stream.reader());
    defer result.deinit(test_allocator);

    switch (result) {
        .Integer => |n| try expect(n == -42),
        else => try expect(false),
    }
}

test "read an empty bulk string" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;

    var content = std.ArrayList(u8).init(test_allocator);
    defer content.deinit();
    const bytes_written = try content.writer().write("$0\r\n\r\n");

    try expect(bytes_written == 6);

    var stream = std.io.fixedBufferStream(content.items);

    var result = try Value.read(test_allocator, stream.reader());
    defer result.deinit(test_allocator);

    switch (result) {
        .BulkString => |s| try expect(std.mem.eql(u8, s, "")),
        else => try expect(false),
    }
}

test "read a bulk string" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;

    var content = std.ArrayList(u8).init(test_allocator);
    defer content.deinit();
    const bytes_written = try content.writer().write("$3\r\nfoo\r\n");

    try expect(bytes_written == 9);

    var stream = std.io.fixedBufferStream(content.items);

    var result = try Value.read(test_allocator, stream.reader());
    defer result.deinit(test_allocator);

    switch (result) {
        .BulkString => |s| try expect(std.mem.eql(u8, s, "foo")),
        else => try expect(false),
    }
}

test "read an empty array" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;

    var content = std.ArrayList(u8).init(test_allocator);
    defer content.deinit();
    const bytes_written = try content.writer().write("*0\r\n");

    try expect(bytes_written == 4);

    var stream = std.io.fixedBufferStream(content.items);

    var result = try Value.read(test_allocator, stream.reader());
    defer result.deinit(test_allocator);

    switch (result) {
        .Array => |arr| try expect(arr.len == 0),
        else => try expect(false),
    }
}

test "read an array of bulk strings" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;

    var content = std.ArrayList(u8).init(test_allocator);
    defer content.deinit();
    const bytes_written = try content.writer().write("*2\r\n$4\r\necho\r\n$13\r\nHello, world!\r\n");

    try expect(bytes_written == 34);

    var stream = std.io.fixedBufferStream(content.items);

    var result = try Value.read(test_allocator, stream.reader());
    defer result.deinit(test_allocator);

    switch (result) {
        .Array => |arr| {
            try expect(arr.len == 2);

            switch (arr[0]) {
                .BulkString => |command| try expect(std.mem.eql(u8, command, "echo")),
                else => try expect(false),
            }

            switch (arr[1]) {
                .BulkString => |arg| try expect(std.mem.eql(u8, arg, "Hello, world!")),
                else => try expect(false),
            }
        },
        else => try expect(false),
    }
}

test "read an array of mixed values" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;

    var content = std.ArrayList(u8).init(test_allocator);
    defer content.deinit();
    const bytes_written = try content.writer().write("*5\r\n$3\r\nfoo\r\n+bar\r\n-oops\r\n:42\r\n:-42\r\n");

    try expect(bytes_written == 37);

    var stream = std.io.fixedBufferStream(content.items);

    var result = try Value.read(test_allocator, stream.reader());
    defer result.deinit(test_allocator);

    switch (result) {
        .Array => |arr| {
            try expect(arr.len == 5);

            switch (arr[0]) {
                .BulkString => |str| try expect(std.mem.eql(u8, str, "foo")),
                else => try expect(false),
            }

            switch (arr[1]) {
                .SimpleString => |str| try expect(std.mem.eql(u8, str, "bar")),
                else => try expect(false),
            }

            switch (arr[2]) {
                .SimpleError => |err| try expect(std.mem.eql(u8, err, "oops")),
                else => try expect(false),
            }

            switch (arr[3]) {
                .Integer => |n| try expect(n == 42),
                else => try expect(false),
            }

            switch (arr[4]) {
                .Integer => |n| try expect(n == -42),
                else => try expect(false),
            }
        },
        else => try expect(false),
    }
}
