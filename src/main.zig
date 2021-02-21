const std = @import("std");
const ansi = @import("ansi.zig");
const testing = std.testing;

const windows = std.os.windows;

const Fg = enum {
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    LightGray,
    DarkGray,
    LightRed,
    LightGreen,
    LightYellow,
    LightBlue,
    LightMagenta,
    LightCyan,
    White,

    fn ansiValue(self: Fg) []const u8 {
        return switch (self) {
            Fg.Black => ansi.Foreground(ansi.Black),
            Fg.Red => ansi.Foreground(ansi.Red),
            Fg.Green => ansi.Foreground(ansi.Green),
            Fg.Yellow => ansi.Foreground(ansi.Yellow),
            Fg.Blue => ansi.Foreground(ansi.Blue),
            Fg.Magenta => ansi.Foreground(ansi.Magenta),
            Fg.Cyan => ansi.Foreground(ansi.Cyan),
            Fg.LightGray => ansi.Foreground(ansi.LightGray),
            Fg.DarkGray => ansi.Foreground(ansi.DarkGray),
            Fg.LightRed => ansi.Foreground(ansi.LightRed),
            Fg.LightGreen => ansi.Foreground(ansi.LightGreen),
            Fg.LightYellow => ansi.Foreground(ansi.LightYellow),
            Fg.LightBlue => ansi.Foreground(ansi.LightBlue),
            Fg.LightMagenta => ansi.Foreground(ansi.LightMagenta),
            Fg.LightCyan => ansi.Foreground(ansi.LightCyan),
            Fg.White => ansi.Foreground(ansi.White),
        };
    }

    fn winConAttribValue(self: Fg) windows.DWORD {
        const FOREGROUND_BLUE      = 0x0001; // text color contains blue.
        const FOREGROUND_GREEN     = 0x0002; // text color contains green.
        const FOREGROUND_RED       = 0x0004; // text color contains red.
        const FOREGROUND_INTENSITY = 0x0008; // text color is intensified.

        return switch (self) {
            Fg.Black => 0,
            Fg.Red => FOREGROUND_RED,
            Fg.Green => FOREGROUND_GREEN,
            Fg.Yellow => FOREGROUND_GREEN | FOREGROUND_RED,
            Fg.Blue => FOREGROUND_BLUE,
            Fg.Magenta => FOREGROUND_RED | FOREGROUND_BLUE,
            Fg.Cyan => FOREGROUND_GREEN | FOREGROUND_BLUE,
            Fg.LightGray => FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE,
            Fg.DarkGray => FOREGROUND_INTENSITY,
            Fg.LightRed => FOREGROUND_RED | FOREGROUND_INTENSITY,
            Fg.LightGreen => FOREGROUND_GREEN | FOREGROUND_INTENSITY,
            Fg.LightYellow => FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_INTENSITY,
            Fg.LightBlue => FOREGROUND_BLUE | FOREGROUND_INTENSITY,
            Fg.LightMagenta => FOREGROUND_RED | FOREGROUND_BLUE | FOREGROUND_INTENSITY,
            Fg.LightCyan => FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_INTENSITY,
            Fg.White => FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE | FOREGROUND_INTENSITY,
        };
    }
};

const ColorWriter = struct {
    const Self = @This();

    writer: std.fs.File.Writer,
    have_color: bool,

    pub fn init(output: std.fs.File) Self {
        return Self {
            .writer = output.writer(),
            .have_color = Self.terminalSupportsAnsiColor(output.handle),
        };
    }

    pub fn writeSeq(self: *const Self, seq: anytype) !void {
        comptime var i: usize = 0;
        comptime var doReset = false;
        inline while (i < seq.len) : (i += 1) {
            const val = seq[i];
            switch (@TypeOf(val)) {
                Fg => {
                    if (self.have_color) {
                        try self.writeAll(val.ansiValue());
                        doReset = true;
                    }
                },
                else => try self.writeAll(val),
            }
        }
        if (doReset)
            try self.writeAll(ansi.Reset());
    }

    pub fn writeAll(self: *const Self, val: []const u8) !void {
        try self.writer.writeAll(val);
    }
   
    extern "kernel32" fn GetConsoleMode(h_console: windows.HANDLE, mode: *windows.DWORD) callconv(if (std.builtin.arch == .i386) .Stdcall else .C) windows.BOOL;    

    pub fn terminalSupportsAnsiColor(h_console: std.os.fd_t) bool {
        if (std.builtin.os.tag == .windows) {
            var mode: windows.DWORD = 0;
            if (Self.GetConsoleMode(h_console, &mode) != windows.FALSE) {
                const ENABLE_VIRTUAL_TERMINAL_PROCESSING: windows.DWORD = 0x0004;
                if (mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING != 0)
                    return true;            
            } 

            // Check if we run under ConEmu
            const wstr = std.unicode.utf8ToUtf16LeStringLiteral;
            if (std.os.getenvW(wstr("ConEmuANSI"))) |val| {
                if (std.mem.eql(u16, val, wstr("ON")))
                    return true;
            }

            return false;
        }

        return true;
    }
};

/// Caller must free memory.
pub fn askString(allocator: *std.mem.Allocator, prompt: []const u8, max_size: usize) ![]u8 {
    const in = std.io.getStdIn().reader();
    const out = ColorWriter.init(std.io.getStdOut());

    try out.writeSeq(.{ Fg.Cyan, "? ", Fg.White, prompt });

    const result = try in.readUntilDelimiterAlloc(allocator, '\n', max_size);
    return if (std.mem.endsWith(u8, result, "\r")) result[0..(result.len - 1)] else result;
}

/// Caller must free memory. Max size is recommended to be a high value, like 512.
pub fn askDirPath(allocator: *std.mem.Allocator, prompt: []const u8, max_size: usize) ![]u8 {
    const out = ColorWriter.init(std.io.getStdOut());

    while (true) {
        const path = try askString(allocator, prompt, max_size);
        if (!std.fs.path.isAbsolute(path)) {
            try out.writeSeq(.{ Fg.Red, "Error: Invalid directory, please try again.\n\n" });
            allocator.free(path);
            continue;
        }

        var dir = std.fs.cwd().openDir(path, std.fs.Dir.OpenDirOptions{}) catch {
            try cw.writeSequence(.{ Fg.Red, "Error: Invalid directory, please try again.\n\n"});
            allocator.free(path);
            continue;
        };

        dir.close();
        return path;
    }
}

pub fn askBool(prompt: []const u8) !bool {
    const in = std.io.getStdIn().reader();
    const out = ColorWriter.init(std.io.getStdOut());

    var buffer: [1]u8 = undefined;

    while (true) {
        try out.writeSeq(.{ Fg.Cyan, "? ", Fg.White, prompt, Fg.DarkGray, " (y/n) > " });

        const read = in.read(&buffer) catch continue;
        try in.skipUntilDelimiterOrEof('\n');

        if (read == 0) return error.EndOfStream;

        switch (buffer[0]) {
            'y' => return true,
            'n' => return false,
            else => continue,
        }
    }
}

pub fn askSelectOne(prompt: []const u8, comptime options: type) !options {
    const in = std.io.getStdIn().reader();
    const out = ColorWriter.init(std.io.getStdOut());

    try out.writeSeq(.{ Fg.Cyan, "? ", Fg.White, prompt, Fg.DarkGray, " (select one)", "\n\n" });

    comptime var max_size: usize = 0;
    inline for (@typeInfo(options).Enum.fields) |option| {
        try out.writeSeq(.{ "  - ", option.name, "\n" });
        if (option.name.len > max_size) max_size = option.name.len;
    }

    while (true) {
        var buffer: [max_size + 1]u8 = undefined;

        try out.writeSeq(.{ Fg.DarkGray, "\n>", " " });

        var result = (in.readUntilDelimiterOrEof(&buffer, '\n') catch {
            try in.skipUntilDelimiterOrEof('\n');
            try out.writeSeq(.{ Fg.Red, "Error: Invalid option, please try again.\n" });
            continue;
        }) orelse return error.EndOfStream;
        result = if (std.mem.endsWith(u8, result, "\r")) result[0..(result.len - 1)] else result;

        inline for (@typeInfo(options).Enum.fields) |option|
            if (std.ascii.eqlIgnoreCase(option.name, result))
                return @intToEnum(options, option.value);
        // return option.value;

        try out.writeSeq(.{ Fg.Red, "Error: Invalid option, please try again.\n" });
    }

    // return undefined;
}

test "basic input functionality" {
    std.debug.print("\n\n", .{});

    std.debug.print("Welcome to the ZLS configuration wizard! (insert mage emoji here)\n", .{});

    // const stdp = try askDirPath(testing.allocator, "What is your Zig lib path (path that contains the 'std' folder)?", 128);
    // const snippet = try askBool("Do you want to enable snippets?");
    // const style = try askBool("Do you want to enable style warnings?");
    const select = try askSelectOne("Which code editor do you use?", enum { VSCode, Sublime, Other });

    // defer testing.allocator.free(select);

    if (select == .VSCode) {}

    std.debug.print("\n\n", .{});
}
