const std = @import("std");

pub const Args = struct {
    directory: ?[]u8,
    dbfilename: ?[]u8,

    const Self = @This();

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try self.write(writer);
    }

    pub fn write(self: Self, writer: anytype) !void {
        try writer.print("Command Line Settings: {{\n", .{});

        if (self.directory) |directory| {
            try writer.print("\tdirectory: {s},\n", .{directory});
        }

        if (self.dbfilename) |dbfilename| {
            try writer.print("\tdbfilename: {s},\n", .{dbfilename});
        }

        try writer.print("}}\n", .{});
    }
};

pub const ProcessCommandLineArgumentsError = error{
    MissingOptionValue,
};

pub fn process_args(args: [][]u8) !Args {
    var result: Args = .{
        .directory = null,
        .dbfilename = null,
    };

    var i: usize = 1;
    while (i < args.len) : (i = i + 1) {
        if (std.mem.eql(u8, "--dir", args[i])) {
            i += 1;

            if (i >= args.len or std.mem.startsWith(u8, args[i], "-")) {}

            result.directory = args[i];
        }

        if (std.mem.eql(u8, "--dbfilename", args[i])) {
            i += 1;

            if (i >= args.len or std.mem.startsWith(u8, args[i], "-")) {
                return ProcessCommandLineArgumentsError.MissingOptionValue;
            }

            result.dbfilename = args[i];
        }
    }

    return result;
}
