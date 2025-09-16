const std = @import("std");
const ChildProcess = std.process.Child;

pub const Listener = enum {
    Status,
    Metadata,

    pub fn args(comptime self: Listener) []const []const u8 {
        return &switch (self) {
            .Status => [_][]const u8{"status"},
            .Metadata => [_][]const u8{
                "--format",
                "{{ artist }} - {{ title }}",
                "metadata",
            },
        };
    }
};

pub const State = struct {
    /// either `playing` or an empty string
    playing: bool,
    /// contains information of current track in the form of `Artist - Song`
    metadata: []const u8,

    writer: *std.Io.Writer,
    mutex: std.Thread.Mutex,

    pub fn jsonStringify(value: State, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("class");
        try jws.write(if (value.playing) "playing" else "");
        try jws.objectField("text");
        try jws.write(value.metadata);
        try jws.endObject();
    }
};

const base_args = [_][]const u8{ "playerctl", "--player", "spotify", "--follow" };

pub fn createProcess(comptime args: []const []const u8, allocator: std.mem.Allocator) ChildProcess {
    var process = ChildProcess.init(base_args ++ args, allocator);
    process.stdout_behavior = .Pipe;
    process.stderr_behavior = .Ignore;
    process.stdin_behavior = .Ignore;
    return process;
}

pub fn listenToProcess(comptime listener: Listener, state: *State, allocator: std.mem.Allocator) !void {
    const args = comptime listener.args();
    var process = createProcess(args, allocator);
    process.spawn() catch |err| {
        const joined_args = std.mem.join(allocator, " ", process.argv) catch "ALLOCATION_FAILED";
        std.debug.print("failed to spawn {s}: {}\n", .{ joined_args, err });
        return;
    };
    defer {
        _ = process.kill() catch |err| {
            const joined_args = std.mem.join(allocator, " ", process.argv) catch "ALLOCATION_FAILED";
            std.debug.print("failed to kill {s}: {}\n", .{ joined_args, err });
        };
    }

    var msg_buf: [256]u8 = undefined;
    var reader = process.stdout.?.reader(&msg_buf);
    while (reader.interface.takeDelimiterExclusive('\n')) |msg| {
        const trimmed = std.mem.trimRight(u8, msg, "\n");

        state.mutex.lock();
        defer state.mutex.unlock();
        switch (listener) {
            .Metadata => state.metadata = trimmed,
            .Status => state.playing = std.mem.eql(u8, "Playing", msg),
        }
        try std.json.fmt(state, .{}).format(state.writer);
        try state.writer.writeByte('\n');
        try state.writer.flush();
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong => std.debug.print("line is too long for buffer: {}\n", .{err}),
        else => std.debug.print("unexpected error: {}\n", .{err}),
    }
}

pub fn main() !void {
    const stdout = std.fs.File.stdout();
    var stdout_buffer: [1024]u8 = undefined;
    var writer = stdout.writer(&stdout_buffer);
    var state = State{ .playing = false, .metadata = "", .writer = &writer.interface, .mutex = std.Thread.Mutex{} };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        const status_thread = try std.Thread.spawn(.{}, listenToProcess, .{ Listener.Status, &state, allocator });
        defer status_thread.join();

        const metadata_thread = try std.Thread.spawn(.{}, listenToProcess, .{ Listener.Metadata, &state, allocator });
        defer metadata_thread.join();
    }
}
