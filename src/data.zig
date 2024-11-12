const std = @import("std");
const RESP = @import("./resp.zig");

const Entry = struct {
    value: []const u8,
    expiry: ?i64,
};

var data: std.StringHashMap(Entry) = undefined;
var lock: std.Thread.RwLock = .{};

pub fn initialize_data(allocator: std.mem.Allocator) void {
    lock.lock();
    defer lock.unlock();

    data.deinit();
    data = std.StringHashMap(Entry).init(allocator);
}

pub fn deinit_data() void {
    lock.lock();
    defer lock.unlock();

    data.deinit();
}

pub fn get(key: []const u8) RESP.Value {
    lock.lockShared();
    defer lock.unlockShared();

    if (data.get(key)) |entry| {
        if (entry.expiry) |expiry| {
            const current_time = std.time.milliTimestamp();

            if (current_time < expiry) {
                return RESP.Value.bulk_string(entry.value);
            }

            return RESP.Value.null_bulk_string();
        }

        return RESP.Value.bulk_string(entry.value);
    }

    return RESP.Value.null_bulk_string();
}

pub fn set(key: []const u8, value: []const u8, expiry_offset: ?i64) !void {
    const expiry = blk: {
        if (expiry_offset) |offset| {
            break :blk std.time.milliTimestamp() + offset;
        }
        break :blk null;
    };

    const entry: Entry = .{
        .value = value,
        .expiry = expiry,
    };

    lock.lock();
    defer lock.unlock();
    try data.put(key, entry);
}
