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

    pub fn handleMessage(self: Listener, msg: []u8) []const u8 {
        remove_newlines(msg);

        return switch (self) {
            .Status => {
                const playing = std.mem.eql(u8, "Playing", msg);
                return if (playing) "playing" else "";
            },
            .Metadata => msg,
        };
    }
};

fn remove_newlines(str: []u8) void {
    for (str, 0..) |c, i| {
        if (c == '\n' or c == '\r') {
            str.ptr[i] = 0;
        }
    }
}

pub const State = struct {
    /// either `playing` or an empty string
    playing: []const u8,
    /// contains information of current track in the form of `Artist - Song`
    metadata: []const u8,

    writer: std.io.AnyWriter,
    mutex: std.Thread.Mutex,

    pub fn jsonStringify(value: @This(), jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("class");
        try jws.write(value.playing);
        try jws.objectField("text");
        try jws.write(value.metadata);
        try jws.endObject();
    }
};

const base_args = [_][]const u8{ "playerctl", "--player", "spotify", "--follow" };

pub fn createProcess(comptime args: []const []const u8, allocator: std.mem.Allocator) ChildProcess {
    var process = ChildProcess.init(base_args ++ args, allocator);
    process.stderr_behavior = .Ignore;
    process.stdin_behavior = .Ignore;
    process.stdout_behavior = .Pipe;
    return process;
}

pub fn listenToProcess(comptime listener: Listener, state: *State) !void {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    const args = comptime listener.args();
    var process = createProcess(args, allocator);
    try process.spawn();

    var msg_buf: [1024]u8 = undefined;
    const reader = process.stdout.?.reader();
    while (try reader.readUntilDelimiterOrEof(&msg_buf, '\n')) |msg| {
        const out = listener.handleMessage(msg);

        state.mutex.lock();
        defer state.mutex.unlock();
        switch (listener) {
            .Status => state.playing = out,
            .Metadata => state.metadata = out,
        }
        try std.json.stringify(state, .{}, state.writer);
        try state.writer.writeByte('\n');
    }

    _ = try process.kill();
}

pub fn main() !void {
    var state = State{ .playing = undefined, .metadata = "", .writer = std.io.getStdOut().writer().any(), .mutex = std.Thread.Mutex{} };

    const status_thread = try std.Thread.spawn(.{}, listenToProcess, .{ Listener.Status, &state });
    const metadata_thread = try std.Thread.spawn(.{}, listenToProcess, .{ Listener.Metadata, &state });

    status_thread.join();
    metadata_thread.join();
}
