const std = @import("std");
const posix = std.posix;
const os = std.os.linux;
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

/// Creates and spawns a process.
pub fn createProcess(comptime args: []const []const u8, allocator: std.mem.Allocator) !ChildProcess {
    var process = ChildProcess.init(base_args ++ args, allocator);
    process.stdout_behavior = .Pipe;
    process.stderr_behavior = .Ignore;
    process.stdin_behavior = .Ignore;

    try process.spawn();

    return process;
}

pub fn listenToProcess(process: ChildProcess, efd: i32) !void {
    const fd = process.stdout.?.handle;
    var event = os.epoll_event{ .events = posix.POLL.IN, .data = .{ .fd = fd } };
    try posix.epoll_ctl(efd, os.EPOLL.CTL_ADD, fd, &event);
}

pub fn main() !void {
    const stdout = std.fs.File.stdout();
    var stdout_buffer: [1024]u8 = undefined;
    var writer = stdout.writer(&stdout_buffer);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const efd = try posix.epoll_create1(os.EPOLL.CLOEXEC);
    defer posix.close(efd);

    const process_status = createProcess(Listener.Status.args(), allocator) catch |err|
        return std.debug.print("failed to spawn {s}: {}\n", .{ std.enums.tagName(Listener, Listener.Status).?, err });
    const handle_status = process_status.stdout.?.handle;

    const process_metadata = createProcess(Listener.Metadata.args(), allocator) catch |err|
        return std.debug.print("failed to spawn {s}: {}\n", .{ std.enums.tagName(Listener, .Metadata).?, err });
    const handle_metadata = process_metadata.stdout.?.handle;

    try listenToProcess(process_status, efd);
    try listenToProcess(process_metadata, efd);

    var state = State{
        .playing = false,
        .metadata = "",
    };

    var ready_list: [8]os.epoll_event = undefined;
    while (true) {
        const ready_count = posix.epoll_wait(efd, &ready_list, -1);
        for (ready_list[0..ready_count]) |ready| {
            const ready_fd = ready.data.fd;
            var buf: [256]u8 = undefined;
            const read = posix.read(ready_fd, &buf) catch 0;
            const output = std.mem.trimEnd(u8, buf[0..read], "\n");

            if (ready_fd == handle_status) {
                state.playing = std.mem.eql(u8, "Playing", output);
            } else if (ready_fd == handle_metadata) {
                allocator.free(state.metadata);
                state.metadata = try allocator.dupe(u8, output);
            }
        }
        try std.json.fmt(state, .{}).format(&writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }
}
