const std = @import("std");

const REDIS_MAGIC_STRING = "REDIS";

// We simply hard code the expected version here.
const REDIS_VERSION_NUMBER = "0011";

pub fn check_header_section(data: []const u8) !bool {
    const first_boundary = REDIS_MAGIC_STRING.len;

    if (!std.mem.eql(u8, REDIS_MAGIC_STRING, data[0..first_boundary])) {
        return false;
    }

    const second_boundary = first_boundary + REDIS_VERSION_NUMBER.len;

    if (!std.mem.eql(u8, REDIS_VERSION_NUMBER, data[first_boundary..second_boundary])) {
        return false;
    }

    return true;
}
