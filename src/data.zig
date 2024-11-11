const std = @import("std");
const RESP = @import("./resp.zig");

var data: std.StringHashMap([]const u8) = undefined;
var lock: std.Thread.RwLock = .{};

pub fn initialize_data(allocator: std.mem.Allocator) void {
    lock.lock();
    defer lock.unlock();

    data = std.StringHashMap([]const u8).init(allocator);
}

pub fn deinit_data() void {
    lock.lock();
    defer lock.unlock();

    data.deinit();
}

pub fn get(key: []const u8) RESP.Value {
    lock.lockShared();
    defer lock.unlockShared();

    if (data.get(key)) |val| {
        return RESP.Value.bulk_string(val);
    } else {
        return RESP.Value.null_bulk_string();
    }
}

pub fn set(key: []const u8, value: []const u8) !void {
    lock.lock();
    defer lock.unlock();

    try data.put(key, value);
}
