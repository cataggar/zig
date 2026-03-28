const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.link_libc) {
        symbol(&fmtmsg, "fmtmsg");
    }
}

extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn dprintf(fd: c_int, fmt: [*:0]const u8, ...) c_int;
extern "c" fn strchr(s: [*:0]u8, c: c_int) ?[*:0]u8;

const O_WRONLY = 1;
const MM_CONSOLE: c_long = 512;
const MM_PRINT: c_long = 256;
const MM_HALT: c_int = 1;
const MM_ERROR: c_int = 2;
const MM_WARNING: c_int = 3;
const MM_INFO: c_int = 4;
const MM_NOCON = 4;
const MM_NOMSG = 1;
const MM_NOTOK = -1;

const empty: [*:0]const u8 = "";

fn strcolcmp(lstr: [*:0]const u8, bstr: [*:0]const u8) bool {
    var i: usize = 0;
    while (lstr[i] != 0 and bstr[i] != 0 and bstr[i] == lstr[i]) : (i += 1) {}
    return lstr[i] == 0 and (bstr[i] == 0 or bstr[i] == ':');
}

fn fmtmsg(
    classification: c_long,
    label: ?[*:0]const u8,
    severity: c_int,
    text: ?[*:0]const u8,
    action: ?[*:0]const u8,
    tag: ?[*:0]const u8,
) callconv(.c) c_int {
    var ret: c_int = 0;

    const errstring: [*:0]const u8 = switch (severity) {
        MM_HALT => "HALT: ",
        MM_ERROR => "ERROR: ",
        MM_WARNING => "WARNING: ",
        MM_INFO => "INFO: ",
        else => empty,
    };

    if (classification & MM_CONSOLE != 0) {
        const consolefd = open("/dev/console", O_WRONLY);
        if (consolefd < 0) {
            ret = MM_NOCON;
        } else {
            if (dprintf(consolefd, "%s%s%s%s%s%s%s%s\n",
                if (label) |l| l else empty, if (label != null) @as([*:0]const u8, ": ") else empty,
                if (severity != 0) errstring else empty, if (text) |t| t else empty,
                if (action != null) @as([*:0]const u8, "\nTO FIX: ") else empty,
                if (action) |a| a else empty, if (action != null) @as([*:0]const u8, " ") else empty,
                if (tag) |t| t else empty) < 1)
                ret = MM_NOCON;
            _ = close(consolefd);
        }
    }

    if (classification & MM_PRINT != 0) {
        var verb: c_int = 0;
        var cmsg: ?[*:0]u8 = getenv("MSGVERB");
        const msgs = [_][*:0]const u8{ "label", "severity", "text", "action", "tag" };

        while (cmsg) |cm| {
            if (cm[0] == 0) break;
            var found = false;
            for (msgs, 0..) |m, i| {
                if (strcolcmp(m, cm)) {
                    verb |= @as(c_int, 1) << @intCast(i);
                    found = true;
                    break;
                }
            }
            if (!found) { verb = 0xFF; break; }
            cmsg = if (strchr(cm, ':')) |p| @ptrCast(@as([*]u8, @ptrCast(p)) + 1) else null;
        }
        if (verb == 0) verb = 0xFF;

        if (dprintf(2, "%s%s%s%s%s%s%s%s\n",
            if (verb & 1 != 0 and label != null) label.? else empty,
            if (verb & 1 != 0 and label != null) @as([*:0]const u8, ": ") else empty,
            if (verb & 2 != 0 and severity != 0) errstring else empty,
            if (verb & 4 != 0 and text != null) text.? else empty,
            if (verb & 8 != 0 and action != null) @as([*:0]const u8, "\nTO FIX: ") else empty,
            if (verb & 8 != 0 and action != null) action.? else empty,
            if (verb & 8 != 0 and action != null) @as([*:0]const u8, " ") else empty,
            if (verb & 16 != 0 and tag != null) tag.? else empty) < 1)
            ret |= MM_NOMSG;
    }

    if (ret & (MM_NOCON | MM_NOMSG) == (MM_NOCON | MM_NOMSG))
        ret = MM_NOTOK;

    return ret;
}
