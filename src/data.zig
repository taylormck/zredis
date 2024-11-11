const std = @import("std");
const RESP = @import("./resp.zig");

var data: std.StringHashMap([]const u8) = undefined;

pub fn initialize_data(allocator: std.mem.Allocator) void {
    data = std.StringHashMap([]const u8).init(allocator);
}

pub fn deinit_data() void {
    data.deinit();
}

pub fn get(key: []const u8) RESP.Value {
    if (data.get(key)) |val| {
        return RESP.Value.bulk_string(val);
    } else {
        return RESP.Value.null_bulk_string();
    }
}

pub fn set(key: []const u8, value: []const u8) !void {
    try data.put(key, value);
}
