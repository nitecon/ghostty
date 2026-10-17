const std = @import("std");
const builtin = @import("builtin");
const windows = @import("windows.zig");
const posix = std.posix;
const compat_fd = @import("../lib/compat/fd.zig");

/// pipe() that works on Windows and POSIX. For POSIX systems, this sets
/// CLOEXEC on the file descriptors.
pub fn pipe() ![2]posix.fd_t {
    switch (builtin.os.tag) {
        else => return compat_fd.pipe2(.{ .CLOEXEC = true }),
        .windows => {
            var read: windows.HANDLE = undefined;
            var write: windows.HANDLE = undefined;
            if (windows.exp.kernel32.CreatePipe(&read, &write, null, 0) == windows.FALSE) {
                return windows.unexpectedError(windows.GetLastError());
            }

            return .{ read, write };
        },
    }
}

/// Release an owned pipe endpoint using the API that created it.
pub fn close(fd: posix.fd_t) void {
    if (builtin.os.tag == .windows) {
        _ = windows.exp.kernel32.CloseHandle(fd);
    } else {
        _ = posix.system.close(fd);
    }
}

/// Write one wakeup byte to a borrowed pipe endpoint. A closed reader is harmless.
pub fn notify(fd: posix.fd_t) !void {
    if (builtin.os.tag == .windows) {
        var written: windows.DWORD = 0;
        if (windows.exp.kernel32.WriteFile(fd, "x", 1, &written, null) == windows.FALSE) {
            const err = windows.GetLastError();
            if (err == .BROKEN_PIPE) return;
            return windows.unexpectedError(err);
        }
        if (written != 1) return error.Unexpected;
    } else {
        switch (posix.errno(posix.system.write(fd, "x", 1))) {
            .SUCCESS, .PIPE => {},
            else => |err| return posix.unexpectedErrno(err),
        }
    }
}
