const std = @import("std");
const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

// Type aliases matching C types
const wchar_t = c_int;
const wint_t = c_uint;
const wctype_t = c_ulong;
const regoff_t = c_int;
const reg_errcode_t = c_int;

// ============================================================
// Public API structures matching musl ABI
// ============================================================
const regex_t = extern struct {
    re_nsub: usize,
    __opaque: ?*anyopaque,
    __padding: [4]?*anyopaque,
    __nsub2: usize,
    __padding2: u8,
};

const regmatch_t = extern struct {
    rm_so: regoff_t,
    rm_eo: regoff_t,
};

const glob_t = extern struct {
    gl_pathc: usize,
    gl_pathv: ?[*]?[*:0]u8,
    gl_offs: usize,
    __flags: c_int,
    __unused1: ?*anyopaque,
    __unused2: c_int,
    __unused3: c_int,
    __unused4: [5]?*anyopaque,
};

// ============================================================
// OS types (Linux x86_64 layout)
// ============================================================
const Timespec = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};

const Stat = extern struct {
    st_dev: u64,
    st_ino: u64,
    st_nlink: u64,
    st_mode: u32,
    st_uid: u32,
    st_gid: u32,
    __pad0: u32,
    st_rdev: u64,
    st_size: i64,
    st_blksize: i64,
    st_blocks: i64,
    st_atim: Timespec,
    st_mtim: Timespec,
    st_ctim: Timespec,
    __unused: [3]i64,
};

const DIR = opaque {};

const Dirent = extern struct {
    d_ino: u64,
    d_off: i64,
    d_reclen: u16,
    d_type: u8,
    d_name: [256]u8,
};

const Passwd = extern struct {
    pw_name: ?[*:0]u8,
    pw_passwd: ?[*:0]u8,
    pw_uid: u32,
    pw_gid: u32,
    pw_gecos: ?[*:0]u8,
    pw_dir: ?[*:0]u8,
    pw_shell: ?[*:0]u8,
};

// ============================================================
// Extern C function declarations
// ============================================================
extern fn mbtowc(pwc: ?*wchar_t, s: ?[*]const u8, n: usize) c_int;
extern fn iswalnum(wc: wint_t) c_int;
extern fn iswalpha(wc: wint_t) c_int;
extern fn iswblank(wc: wint_t) c_int;
extern fn iswcntrl(wc: wint_t) c_int;
extern fn iswdigit(wc: wint_t) c_int;
extern fn iswgraph(wc: wint_t) c_int;
extern fn iswlower(wc: wint_t) c_int;
extern fn iswprint(wc: wint_t) c_int;
extern fn iswpunct(wc: wint_t) c_int;
extern fn iswspace(wc: wint_t) c_int;
extern fn iswupper(wc: wint_t) c_int;
extern fn iswxdigit(wc: wint_t) c_int;
extern fn towlower(wc: wint_t) wint_t;
extern fn towupper(wc: wint_t) wint_t;
extern fn iswctype(wc: wint_t, desc: wctype_t) c_int;
extern fn wctype(name: [*:0]const u8) wctype_t;
extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern fn strlen(s: [*:0]const u8) usize;
extern fn strnlen(s: [*]const u8, maxlen: usize) usize;
extern fn strncmp(s1: [*]const u8, s2: [*]const u8, n: usize) c_int;
extern fn strcmp(s1: [*:0]const u8, s2: [*:0]const u8) c_int;
extern fn strchr(s: [*:0]const u8, c: c_int) ?[*]u8;
extern fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern fn memset(s: *anyopaque, c: c_int, n: usize) *anyopaque;
extern fn qsort(base: *anyopaque, nmemb: usize, size: usize, compar: *const fn (*const anyopaque, *const anyopaque) callconv(.c) c_int) void;
extern fn opendir(name: [*:0]const u8) ?*DIR;
extern fn readdir(dirp: *DIR) ?*Dirent;
extern fn closedir(dirp: *DIR) c_int;
extern fn stat(path: [*:0]const u8, buf: *Stat) c_int;
extern fn lstat(path: [*:0]const u8, buf: *Stat) c_int;
extern fn getenv(name: [*:0]const u8) ?[*:0]u8;
extern fn getuid() u32;
extern fn getpwnam_r(name: [*:0]const u8, pwd: *Passwd, buf: [*]u8, buflen: usize, result: *?*Passwd) c_int;
extern fn getpwuid_r(uid: u32, pwd: *Passwd, buf: [*]u8, buflen: usize, result: *?*Passwd) c_int;
extern fn __strchrnul(s: [*]const u8, c: c_int) [*]u8;

// ============================================================
// Constants
// ============================================================
const REG_OK: reg_errcode_t = 0;
const REG_NOMATCH: reg_errcode_t = 1;
const REG_BADPAT: reg_errcode_t = 2;
const REG_ECOLLATE: reg_errcode_t = 3;
const REG_ECTYPE: reg_errcode_t = 4;
const REG_EESCAPE: reg_errcode_t = 5;
const REG_ESUBREG: reg_errcode_t = 6;
const REG_EBRACK: reg_errcode_t = 7;
const REG_EPAREN: reg_errcode_t = 8;
const REG_EBRACE: reg_errcode_t = 9;
const REG_BADBR: reg_errcode_t = 10;
const REG_ERANGE: reg_errcode_t = 11;
const REG_ESPACE: reg_errcode_t = 12;
const REG_BADRPT: reg_errcode_t = 13;
const REG_EXTENDED: c_int = 1;
const REG_ICASE: c_int = 2;
const REG_NEWLINE: c_int = 4;
const REG_NOSUB: c_int = 8;
const REG_NOTBOL: c_int = 1;
const REG_NOTEOL: c_int = 2;

const FNM_NOMATCH: c_int = 1;
const FNM_PATHNAME: c_int = 1;
const FNM_NOESCAPE: c_int = 2;
const FNM_PERIOD: c_int = 4;
const FNM_LEADING_DIR: c_int = 8;
const FNM_CASEFOLD: c_int = 16;

const GLOB_ERR: c_int = 1;
const GLOB_MARK: c_int = 2;
const GLOB_NOSORT: c_int = 4;
const GLOB_DOOFFS: c_int = 8;
const GLOB_NOCHECK: c_int = 16;
const GLOB_APPEND: c_int = 32;
const GLOB_NOESCAPE: c_int = 64;
const GLOB_PERIOD: c_int = 128;
const GLOB_TILDE: c_int = 0x800;
const GLOB_TILDE_CHECK: c_int = 0x1000;
const GLOB_NOSPACE: c_int = 1;
const GLOB_ABORTED: c_int = 2;
const GLOB_NOMATCH: c_int = 3;

const ASSERT_AT_BOL: c_int = 1;
const ASSERT_AT_EOL: c_int = 2;
const ASSERT_CHAR_CLASS: c_int = 4;
const ASSERT_CHAR_CLASS_NEG: c_int = 8;
const ASSERT_AT_BOW: c_int = 16;
const ASSERT_AT_EOW: c_int = 32;
const ASSERT_AT_WB: c_int = 64;
const ASSERT_AT_WB_NEG: c_int = 128;
const ASSERT_BACKREF: c_int = 256;

const TRE_CHAR_MAX: c_int = 0x10ffff;
const TRE_MEM_BLOCK_SIZE: usize = 1024;
const RE_DUP_MAX: c_int = 255;
const CHARCLASS_NAME_MAX: usize = 14;
const PATH_MAX: usize = 4096;
const MB_LEN_MAX: usize = 4;
const MAX_NEG_CLASSES: usize = 64;
const DT_DIR: u8 = 4;
const DT_LNK: u8 = 10;
const DT_REG: u8 = 8;
const ENOMEM: c_int = 12;
const ENOENT: c_int = 2;

// AST node types (integers, not enum, to match C)
const LITERAL: c_int = 0;
const CATENATION: c_int = 1;
const ITERATION: c_int = 2;
const UNION: c_int = 3;
// Special literal codes
const EMPTY_LIT: c_int = -1;
const ASSERTION_LIT: c_int = -2;
const TAG_LIT: c_int = -3;
const BACKREF_LIT: c_int = -4;
// Tag directions
const TRE_TAG_MINIMIZE: c_int = 0;
const TRE_TAG_MAXIMIZE: c_int = 1;

// ============================================================
// Internal types
// ============================================================
const TreList = struct {
    data: ?*anyopaque,
    next: ?*TreList,
};

// TreMemStruct - note: TreMem = *TreMemStruct in C
const TreMemStruct = struct {
    blocks: ?*TreList,
    current: ?*TreList,
    ptr: usize, // raw pointer value to current position
    n: usize,
    failed: c_int,
    provided: ?*anyopaque,
};
const TreMem = *TreMemStruct;

const TnfaTransitionU = extern union {
    char_class: wctype_t, // renamed from 'class' (keyword in Zig)
    backref: c_int,
};

const TnfaTransition = struct {
    code_min: wint_t,
    code_max: wint_t,
    state: ?*TnfaTransition,
    state_id: c_int,
    tags: ?[*]c_int,
    assertions: c_int,
    u: TnfaTransitionU,
    neg_classes: ?[*]wctype_t,
};

const TreSubmatchData = struct {
    so_tag: c_int,
    eo_tag: c_int,
    parents: ?[*]c_int,
};

const Tnfa = struct {
    transitions: ?[*]TnfaTransition,
    num_transitions: c_uint,
    initial: ?[*]TnfaTransition,
    final: ?*TnfaTransition,
    submatch_data: ?[*]TreSubmatchData,
    firstpos_chars: ?[*]u8,
    first_char: c_int,
    num_submatches: c_uint,
    tag_directions: ?[*]c_int,
    minimal_tags: ?[*]c_int,
    num_tags: c_int,
    num_minimals: c_int,
    end_tag: c_int,
    num_states: c_int,
    cflags: c_int,
    have_backrefs: c_int,
    have_approx: c_int,
};

// AST types
const TrePosAndTags = struct {
    position: c_int,
    code_min: c_int,
    code_max: c_int,
    tags: ?[*]c_int,
    assertions: c_int,
    char_class: wctype_t, // renamed from 'class'
    neg_classes: ?[*]wctype_t,
    backref: c_int,
};

const TreAstNode = struct {
    node_type: c_int, // LITERAL, CATENATION, ITERATION, UNION
    obj: ?*anyopaque,
    nullable: c_int,
    submatch_id: c_int,
    num_submatches: c_int,
    num_tags: c_int,
    firstpos: ?[*]TrePosAndTags,
    lastpos: ?[*]TrePosAndTags,
};

const TreLiteral = struct {
    code_min: c_long,
    code_max: c_long,
    position: c_int,
    char_class: wctype_t, // renamed from 'class'
    neg_classes: ?[*]wctype_t,
};

const TreCatenation = struct {
    left: ?*TreAstNode,
    right: ?*TreAstNode,
};

const TreIteration = struct {
    arg: ?*TreAstNode,
    min: c_int,
    max: c_int,
    minimal: u1,
};

const TreUnion = struct {
    left: ?*TreAstNode,
    right: ?*TreAstNode,
};

const TreStackItem = extern union {
    voidptr_value: ?*anyopaque,
    int_value: c_int,
};

const TreStack = struct {
    size: c_int,
    max_size: c_int,
    increment: c_int,
    ptr: c_int,
    stack: ?[*]TreStackItem,
};

const TreParseCtx = struct {
    mem: ?TreMem,
    stack: ?*TreStack,
    n: ?*TreAstNode,
    s: [*]const u8,
    start: [*]const u8,
    submatch_id: c_int,
    position: c_int,
    max_backref: c_int,
    cflags: c_int,
};

const TreTagStates = struct {
    tag: c_int,
    next_tag: c_int,
};

const LiteralsArr = struct {
    mem: ?TreMem,
    a: ?[*]?*TreLiteral,
    len: c_int,
    cap: c_int,
};

const NegClasses = struct {
    negate: c_int,
    len: c_int,
    a: [MAX_NEG_CLASSES]wctype_t,
};

// Addtags symbols
const ADDTAGS_RECURSE: c_int = 0;
const ADDTAGS_AFTER_ITERATION: c_int = 1;
const ADDTAGS_AFTER_UNION_LEFT: c_int = 2;
const ADDTAGS_AFTER_UNION_RIGHT: c_int = 3;
const ADDTAGS_AFTER_CAT_LEFT: c_int = 4;
const ADDTAGS_AFTER_CAT_RIGHT: c_int = 5;
const ADDTAGS_SET_SUBMATCH_END: c_int = 6;

// Copy AST symbols
const COPY_RECURSE: c_int = 0;
const COPY_SET_RESULT_PTR: c_int = 1;
const COPY_REMOVE_TAGS: c_int = 1;
const COPY_MAXIMIZE_FIRST_TAG: c_int = 2;

// Expand AST symbols
const EXPAND_RECURSE: c_int = 0;
const EXPAND_AFTER_ITER: c_int = 1;

// NFL symbols
const NFL_RECURSE: c_int = 0;
const NFL_POST_UNION: c_int = 1;
const NFL_POST_CATENATION: c_int = 2;
const NFL_POST_ITERATION: c_int = 3;

// fnmatch internal codes
const FNM_END: c_int = 0;
const FNM_UNMATCHABLE: c_int = -2;
const FNM_BRACKET: c_int = -3;
const FNM_QUESTION: c_int = -4;
const FNM_STAR: c_int = -5;

// ============================================================
// Helper functions
// ============================================================

fn alignPad(ptr: usize, comptime T: type) usize {
    const s = @sizeOf(T);
    const r = ptr % s;
    return if (r != 0) s - r else 0;
}

fn isSpecial(lit: *TreLiteral) bool {
    return lit.code_min < 0;
}

fn isTag(lit: *TreLiteral) bool {
    return lit.code_min == TAG_LIT;
}

fn isBackref(lit: *TreLiteral) bool {
    return lit.code_min == BACKREF_LIT;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn treMax(a: c_int, b: c_int) c_int {
    return if (a >= b) a else b;
}

fn treMin(a: c_int, b: c_int) c_int {
    return if (a <= b) a else b;
}

fn isWordChar(c: wint_t) bool {
    return c == '_' or iswalnum(c) != 0;
}

fn sIsDir(mode: u32) bool {
    return (mode & 0o170000) == 0o040000;
}

// ============================================================
// tre_mem functions
// ============================================================

fn treMemNew() ?TreMem {
    const p = std.c.calloc(1, @sizeOf(TreMemStruct)) orelse return null;
    const mem: TreMem = @ptrCast(@alignCast(p));
    return mem;
}

fn treMemDestroy(mem: TreMem) void {
    var l: ?*TreList = mem.blocks;
    while (l) |node| {
        std.c.free(node.data);
        const tmp = node.next;
        std.c.free(@ptrCast(node));
        l = tmp;
    }
    std.c.free(@ptrCast(mem));
}

fn treMemAllocImpl(mem: TreMem, provided: c_int, provided_block: ?*anyopaque, zero: c_int, size: usize) ?*anyopaque {
    if (mem.failed != 0) return null;

    if (mem.n < size) {
        if (provided != 0) {
            if (provided_block == null) {
                mem.failed = 1;
                return null;
            }
            mem.ptr = @intFromPtr(provided_block.?);
            mem.n = TRE_MEM_BLOCK_SIZE;
        } else {
            const bs: usize = if (size * 8 > TRE_MEM_BLOCK_SIZE) size * 8 else TRE_MEM_BLOCK_SIZE;
            const l: *TreList = @ptrCast(@alignCast(std.c.malloc(@sizeOf(TreList)) orelse {
                mem.failed = 1;
                return null;
            }));
            l.data = std.c.malloc(bs) orelse {
                std.c.free(@ptrCast(l));
                mem.failed = 1;
                return null;
            };
            l.next = null;
            if (mem.current) |cur| cur.next = l;
            if (mem.blocks == null) mem.blocks = l;
            mem.current = l;
            mem.ptr = @intFromPtr(l.data.?);
            mem.n = bs;
        }
    }

    var alloc_size = size;
    alloc_size += alignPad(mem.ptr + alloc_size, c_long);

    const ptr = mem.ptr;
    mem.ptr += alloc_size;
    mem.n -= alloc_size;

    if (zero != 0) {
        const p: [*]u8 = @ptrFromInt(ptr);
        @memset(p[0..alloc_size], 0);
    }

    return @ptrFromInt(ptr);
}

fn treMemAlloc(mem: TreMem, size: usize) ?*anyopaque {
    return treMemAllocImpl(mem, 0, null, 0, size);
}

fn treMemCalloc(mem: TreMem, size: usize) ?*anyopaque {
    return treMemAllocImpl(mem, 0, null, 1, size);
}

// ============================================================
// Stack functions
// ============================================================

fn treStackNew(size: c_int, max_size: c_int, increment: c_int) ?*TreStack {
    const s: *TreStack = @ptrCast(@alignCast(std.c.malloc(@sizeOf(TreStack)) orelse return null));
    s.stack = @ptrCast(@alignCast(std.c.malloc(@sizeOf(TreStackItem) * @as(usize, @intCast(size))) orelse {
        std.c.free(@ptrCast(s));
        return null;
    }));
    s.size = size;
    s.max_size = max_size;
    s.increment = increment;
    s.ptr = 0;
    return s;
}

fn treStackDestroy(s: *TreStack) void {
    std.c.free(@ptrCast(s.stack));
    std.c.free(@ptrCast(s));
}

fn treStackNumObjects(s: *TreStack) c_int {
    return s.ptr;
}

fn treStackPush(s: *TreStack, value: TreStackItem) reg_errcode_t {
    if (s.ptr < s.size) {
        s.stack.?[@intCast(s.ptr)] = value;
        s.ptr += 1;
    } else {
        if (s.size >= s.max_size) return REG_ESPACE;
        var new_size = s.size + s.increment;
        if (new_size > s.max_size) new_size = s.max_size;
        const new_buf: [*]TreStackItem = @ptrCast(@alignCast(std.c.realloc(
            @ptrCast(s.stack),
            @sizeOf(TreStackItem) * @as(usize, @intCast(new_size)),
        ) orelse return REG_ESPACE));
        s.size = new_size;
        s.stack = new_buf;
        return treStackPush(s, value);
    }
    return REG_OK;
}

fn treStackPushInt(s: *TreStack, value: c_int) reg_errcode_t {
    var item: TreStackItem = undefined;
    item.int_value = value;
    return treStackPush(s, item);
}

fn treStackPushVoidptr(s: *TreStack, value: ?*anyopaque) reg_errcode_t {
    var item: TreStackItem = undefined;
    item.voidptr_value = value;
    return treStackPush(s, item);
}

fn treStackPopInt(s: *TreStack) c_int {
    s.ptr -= 1;
    return s.stack.?[@intCast(s.ptr)].int_value;
}

fn treStackPopVoidptr(s: *TreStack) ?*anyopaque {
    s.ptr -= 1;
    return s.stack.?[@intCast(s.ptr)].voidptr_value;
}

// ============================================================
// AST builder functions
// ============================================================

fn treAstNewNode(mem: TreMem, node_type: c_int, obj: ?*anyopaque) ?*TreAstNode {
    const node: *TreAstNode = @ptrCast(@alignCast(treMemCalloc(mem, @sizeOf(TreAstNode)) orelse return null));
    if (obj == null) return null;
    node.obj = obj;
    node.node_type = node_type;
    node.nullable = -1;
    node.submatch_id = -1;
    return node;
}

fn treAstNewLiteral(mem: TreMem, code_min: c_int, code_max: c_int, position: c_int) ?*TreAstNode {
    const lit: *TreLiteral = @ptrCast(@alignCast(treMemCalloc(mem, @sizeOf(TreLiteral)) orelse return null));
    const node = treAstNewNode(mem, LITERAL, @ptrCast(lit)) orelse return null;
    lit.code_min = code_min;
    lit.code_max = code_max;
    lit.position = position;
    return node;
}

fn treAstNewIter(mem: TreMem, arg: ?*TreAstNode, min: c_int, max: c_int, minimal: u1) ?*TreAstNode {
    const iter: *TreIteration = @ptrCast(@alignCast(treMemCalloc(mem, @sizeOf(TreIteration)) orelse return null));
    const node = treAstNewNode(mem, ITERATION, @ptrCast(iter)) orelse return null;
    iter.arg = arg;
    iter.min = min;
    iter.max = max;
    iter.minimal = minimal;
    node.num_submatches = if (arg) |a| a.num_submatches else 0;
    return node;
}

fn treAstNewUnion(mem: TreMem, left: ?*TreAstNode, right: ?*TreAstNode) ?*TreAstNode {
    if (left == null) return right;
    const un: *TreUnion = @ptrCast(@alignCast(treMemCalloc(mem, @sizeOf(TreUnion)) orelse return null));
    const node = treAstNewNode(mem, UNION, @ptrCast(un)) orelse return null;
    if (right == null) return null;
    un.left = left;
    un.right = right;
    node.num_submatches = (if (left) |l| l.num_submatches else 0) + (if (right) |r| r.num_submatches else 0);
    return node;
}

fn treAstNewCatenation(mem: TreMem, left: ?*TreAstNode, right: ?*TreAstNode) ?*TreAstNode {
    if (left == null) return right;
    const cat: *TreCatenation = @ptrCast(@alignCast(treMemCalloc(mem, @sizeOf(TreCatenation)) orelse return null));
    const node = treAstNewNode(mem, CATENATION, @ptrCast(cat)) orelse return null;
    cat.left = left;
    cat.right = right;
    node.num_submatches = (if (left) |l| l.num_submatches else 0) + (if (right) |r| r.num_submatches else 0);
    return node;
}


// ============================================================
// Parser macros (expanded inline)
// ============================================================

const TreMacro = struct { c: u8, expansion: [*:0]const u8 };

const treMacros = [_]TreMacro{
    .{ .c = 't', .expansion = "\t" },
    .{ .c = 'n', .expansion = "\n" },
    .{ .c = 'r', .expansion = "\r" },
    .{ .c = 'f', .expansion = "\x0C" },
    .{ .c = 'a', .expansion = "\x07" },
    .{ .c = 'e', .expansion = "\x1b" },
    .{ .c = 'w', .expansion = "[[:alnum:]_]" },
    .{ .c = 'W', .expansion = "[^[:alnum:]_]" },
    .{ .c = 's', .expansion = "[[:space:]]" },
    .{ .c = 'S', .expansion = "[^[:space:]]" },
    .{ .c = 'd', .expansion = "[[:digit:]]" },
    .{ .c = 'D', .expansion = "[^[:digit:]]" },
    .{ .c = 0, .expansion = "" },
};

fn treExpandMacro(s: [*]const u8) ?[*:0]const u8 {
    var i: usize = 0;
    while (treMacros[i].c != 0 and treMacros[i].c != s[0]) : (i += 1) {}
    return if (treMacros[i].c != 0) treMacros[i].expansion else null;
}

fn treCompareLit(a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int {
    const la: *const ?*TreLiteral = @ptrCast(@alignCast(a));
    const lb: *const ?*TreLiteral = @ptrCast(@alignCast(b));
    return @intCast(la.*.?.code_min - lb.*.?.code_min);
}

fn treNewLit(p: *LiteralsArr) ?*TreLiteral {
    if (p.len >= p.cap) {
        if (p.cap >= (1 << 15)) return null;
        p.cap *= 2;
        const new_a: ?[*]?*TreLiteral = @ptrCast(@alignCast(std.c.realloc(
            @ptrCast(p.a),
            @as(usize, @intCast(p.cap)) * @sizeOf(?*TreLiteral),
        )));
        if (new_a == null) return null;
        p.a = new_a;
    }
    const idx: usize = @intCast(p.len);
    p.len += 1;
    const lit: ?*TreLiteral = @ptrCast(@alignCast(treMemCalloc(p.mem.?, @sizeOf(TreLiteral))));
    p.a.?[idx] = lit;
    return lit;
}

fn addIcaseLiterals(ls: *LiteralsArr, min: c_int, max: c_int) c_int {
    var c: wint_t = @intCast(min);
    const cmax: wint_t = @intCast(max);
    while (c <= cmax) {
        var b: wint_t = undefined;
        var e: wint_t = undefined;
        if (iswlower(c) != 0) {
            b = towupper(c);
            e = b;
            c += 1;
            e += 1;
            while (c <= cmax) : ({ c += 1; e += 1; }) {
                if (towupper(c) != e) break;
            }
        } else if (iswupper(c) != 0) {
            b = towlower(c);
            e = b;
            c += 1;
            e += 1;
            while (c <= cmax) : ({ c += 1; e += 1; }) {
                if (towlower(c) != e) break;
            }
        } else {
            c += 1;
            continue;
        }
        const lit = treNewLit(ls) orelse return -1;
        lit.code_min = @intCast(b);
        lit.code_max = @intCast(e - 1);
        lit.position = -1;
    }
    return 0;
}

fn parseBracketTerms(ctx: *TreParseCtx, s_in: [*]const u8, ls: *LiteralsArr, neg: *NegClasses) reg_errcode_t {
    const start = s_in;
    var s: [*]const u8 = s_in;
    var char_class: wctype_t = 0;
    var min_code: c_int = 0;
    var max_code: c_int = 0;
    var wc: wchar_t = 0;
    var len: c_int = 0;

    while (true) {
        char_class = 0;
        len = mbtowc(&wc, s, std.math.maxInt(usize));
        if (len <= 0) return if (s[0] != 0) REG_BADPAT else REG_EBRACK;
        if (s[0] == ']' and s != start) {
            ctx.s = s + 1;
            return REG_OK;
        }
        if (s[0] == '-' and s != start and s[1] != ']' and
            (s[1] != '-' or s[2] == ']'))
            return REG_ERANGE;
        if (s[0] == '[' and (s[1] == '.' or s[1] == '='))
            return REG_ECOLLATE;
        if (s[0] == '[' and s[1] == ':') {
            var tmp: [CHARCLASS_NAME_MAX + 1]u8 = undefined;
            s += 2;
            var clen: usize = 0;
            while (clen < CHARCLASS_NAME_MAX and s[clen] != 0) : (clen += 1) {
                if (s[clen] == ':') {
                    @memcpy(tmp[0..clen], s[0..clen]);
                    tmp[clen] = 0;
                    char_class = wctype(@ptrCast(&tmp));
                    break;
                }
            }
            if (char_class == 0 or s[clen + 1] != ']')
                return REG_ECTYPE;
            min_code = 0;
            max_code = TRE_CHAR_MAX;
            s += clen + 2;
        } else {
            min_code = wc;
            max_code = wc;
            s += @intCast(len);
            if (s[0] == '-' and s[1] != ']') {
                s += 1;
                len = mbtowc(&wc, s, std.math.maxInt(usize));
                max_code = wc;
                if (len <= 0 or min_code > max_code)
                    return REG_ERANGE;
                s += @intCast(len);
            }
        }
        if (char_class != 0 and neg.negate != 0) {
            if (neg.len >= MAX_NEG_CLASSES) return REG_ESPACE;
            neg.a[@intCast(neg.len)] = char_class;
            neg.len += 1;
        } else {
            const lit = treNewLit(ls) orelse return REG_ESPACE;
            lit.code_min = min_code;
            lit.code_max = max_code;
            lit.char_class = char_class;
            lit.position = -1;
            if (ctx.cflags & REG_ICASE != 0 and char_class == 0) {
                if (addIcaseLiterals(ls, min_code, max_code) != 0)
                    return REG_ESPACE;
            }
        }
    }
}

fn parseBracket(ctx: *TreParseCtx, s_in: [*]const u8) reg_errcode_t {
    var node: ?*TreAstNode = null;
    var nc: ?[*]wctype_t = null;
    var ls = LiteralsArr{
        .mem = ctx.mem,
        .len = 0,
        .cap = 32,
        .a = @ptrCast(@alignCast(std.c.malloc(32 * @sizeOf(?*TreLiteral)))),
    };
    if (ls.a == null) return REG_ESPACE;

    var neg = NegClasses{
        .negate = if (s_in[0] == '^') 1 else 0,
        .len = 0,
        .a = undefined,
    };
    const s = if (neg.negate != 0) s_in + 1 else s_in;

    var err = parseBracketTerms(ctx, s, &ls, &neg);
    if (err != REG_OK) {
        std.c.free(@ptrCast(ls.a));
        ctx.position += 1;
        ctx.n = node;
        return err;
    }

    bracket_done: {
        if (neg.negate != 0) {
            if (ctx.cflags & REG_NEWLINE != 0) {
                const lit = treNewLit(&ls) orelse {
                    err = REG_ESPACE;
                    break :bracket_done;
                };
                lit.code_min = '\n';
                lit.code_max = '\n';
                lit.position = -1;
            }
            qsort(@ptrCast(ls.a.?), @intCast(ls.len), @sizeOf(?*TreLiteral), treCompareLit);
            const lit2 = treNewLit(&ls) orelse {
                err = REG_ESPACE;
                break :bracket_done;
            };
            lit2.code_min = TRE_CHAR_MAX + 1;
            lit2.code_max = TRE_CHAR_MAX + 1;
            lit2.position = -1;
            if (neg.len > 0) {
                nc = @ptrCast(@alignCast(treMemAlloc(ctx.mem.?, @as(usize, @intCast(neg.len + 1)) * @sizeOf(wctype_t)) orelse {
                    err = REG_ESPACE;
                    break :bracket_done;
                }));
                for (0..@as(usize, @intCast(neg.len))) |i| nc.?[i] = neg.a[i];
                nc.?[@intCast(neg.len)] = 0;
            }
        }

        var negmax: c_int = 0;
        var negmin: c_int = 0;
        var i: c_int = 0;
        while (i < ls.len) : (i += 1) {
            const lit = ls.a.?[@intCast(i)].?;
            const min_c = lit.code_min;
            const max_c = lit.code_max;
            if (neg.negate != 0) {
                if (min_c <= negmin) {
                    negmin = treMax(@intCast(max_c + 1), negmin);
                    continue;
                }
                negmax = @intCast(min_c - 1);
                lit.code_min = negmin;
                lit.code_max = negmax;
                negmin = @intCast(max_c + 1);
            }
            lit.position = ctx.position;
            lit.neg_classes = nc;
            const n = treAstNewNode(ctx.mem.?, LITERAL, @ptrCast(lit));
            node = treAstNewUnion(ctx.mem.?, node, n);
            if (node == null) {
                err = REG_ESPACE;
                break;
            }
        }
    }

    std.c.free(@ptrCast(ls.a));
    ctx.position += 1;
    ctx.n = node;
    return err;
}

fn parseDupCount(s_in: [*]const u8, n: *c_int) [*]const u8 {
    n.* = -1;
    var s = s_in;
    if (!isDigit(s[0])) return s;
    n.* = 0;
    while (true) {
        n.* = 10 * n.* + (@as(c_int, s[0]) - '0');
        s += 1;
        if (!isDigit(s[0]) or n.* > RE_DUP_MAX) break;
    }
    return s;
}

fn parseDup(s_in: [*]const u8, ere: c_int, pmin: *c_int, pmax: *c_int) ?[*]const u8 {
    var min_v: c_int = 0;
    var max_v: c_int = 0;
    var s = parseDupCount(s_in, &min_v);
    if (s[0] == ',') {
        s = parseDupCount(s + 1, &max_v);
    } else {
        max_v = min_v;
    }
    if ((max_v < min_v and max_v >= 0) or
        max_v > RE_DUP_MAX or
        min_v > RE_DUP_MAX or
        min_v < 0)
        return null;
    if (ere == 0) {
        if (s[0] != '\\') return null;
        s += 1;
    }
    if (s[0] != '}') return null;
    s += 1;
    pmin.* = min_v;
    pmax.* = max_v;
    return s;
}

fn hexval(c: u8) c_int {
    if (c -% '0' < 10) return c - '0';
    const cl = c | 32;
    if (cl -% 'a' < 6) return cl - 'a' + 10;
    return -1;
}

fn marksub(ctx: *TreParseCtx, node_in: ?*TreAstNode, subid: c_int) reg_errcode_t {
    var node = node_in orelse return REG_ESPACE;
    if (node.submatch_id >= 0) {
        var n = treAstNewLiteral(ctx.mem.?, EMPTY_LIT, -1, -1) orelse return REG_ESPACE;
        n = treAstNewCatenation(ctx.mem.?, n, node) orelse return REG_ESPACE;
        n.num_submatches = node.num_submatches;
        node = n;
    }
    node.submatch_id = subid;
    node.num_submatches += 1;
    ctx.n = node;
    return REG_OK;
}

fn parseAtom(ctx: *TreParseCtx, s_in: [*]const u8) reg_errcode_t {
    const ere: c_int = ctx.cflags & REG_EXTENDED;
    var s: [*]const u8 = s_in;
    var node: ?*TreAstNode = null;

    // We use a labeled block to simulate goto end
    got_node: {
        switch (s[0]) {
            '[' => return parseBracket(ctx, s + 1),
            '\\' => {
                const p = treExpandMacro(s + 1);
                if (p) |expansion| {
                    const err = parseAtom(ctx, expansion);
                    ctx.s = s + 2;
                    return err;
                }
                s += 1;
                switch (s[0]) {
                    0 => return REG_EESCAPE,
                    'b' => {
                        node = treAstNewLiteral(ctx.mem.?, ASSERTION_LIT, ASSERT_AT_WB, -1);
                        s += 1;
                    },
                    'B' => {
                        node = treAstNewLiteral(ctx.mem.?, ASSERTION_LIT, ASSERT_AT_WB_NEG, -1);
                        s += 1;
                    },
                    '<' => {
                        node = treAstNewLiteral(ctx.mem.?, ASSERTION_LIT, ASSERT_AT_BOW, -1);
                        s += 1;
                    },
                    '>' => {
                        node = treAstNewLiteral(ctx.mem.?, ASSERTION_LIT, ASSERT_AT_EOW, -1);
                        s += 1;
                    },
                    'x' => {
                        s += 1;
                        var v: c_int = 0;
                        var hlen: c_int = 2;
                        if (s[0] == '{') {
                            hlen = 8;
                            s += 1;
                        }
                        var hi: c_int = 0;
                        while (hi < hlen and v < 0x110000) : (hi += 1) {
                            const hc = hexval(s[@intCast(hi)]);
                            if (hc < 0) break;
                            v = 16 * v + hc;
                        }
                        s += @intCast(hi);
                        if (hlen == 8) {
                            if (s[0] != '}') return REG_EBRACE;
                            s += 1;
                        }
                        node = treAstNewLiteral(ctx.mem.?, v, v, ctx.position);
                        ctx.position += 1;
                        s -= 1; // will be incremented below
                        s += 1;
                    },
                    '{', '+', '?' => {
                        if (ere == 0) return REG_BADRPT;
                        // ERE: fall through to '|' case → EMPTY
                        node = treAstNewLiteral(ctx.mem.?, EMPTY_LIT, -1, -1);
                        s -= 1; // back to before the '\\', s will not advance
                        break :got_node;
                    },
                    '|' => {
                        if (ere == 0) {
                            // BRE: treat \| as alternation marker (empty node, s stays)
                            node = treAstNewLiteral(ctx.mem.?, EMPTY_LIT, -1, -1);
                            s -= 1;
                            break :got_node;
                        }
                        // ERE: EMPTY
                        node = treAstNewLiteral(ctx.mem.?, EMPTY_LIT, -1, -1);
                        s += 1;
                    },
                    else => {
                        if (ere == 0 and s[0] >= '1' and s[0] <= '9') {
                            const val: c_int = s[0] - '0';
                            node = treAstNewLiteral(ctx.mem.?, BACKREF_LIT, val, ctx.position);
                            ctx.position += 1;
                            ctx.max_backref = treMax(val, ctx.max_backref);
                        } else {
                            // Treat as literal
                            var wc: wchar_t = 0;
                            const wlen = mbtowc(&wc, s, std.math.maxInt(usize));
                            if (wlen < 0) return REG_BADPAT;
                            if (ctx.cflags & REG_ICASE != 0 and
                                (iswupper(@intCast(wc)) != 0 or iswlower(@intCast(wc)) != 0))
                            {
                                const tmp1 = treAstNewLiteral(ctx.mem.?, @intCast(towupper(@intCast(wc))), @intCast(towupper(@intCast(wc))), ctx.position);
                                const tmp2 = treAstNewLiteral(ctx.mem.?, @intCast(towlower(@intCast(wc))), @intCast(towlower(@intCast(wc))), ctx.position);
                                node = if (tmp1 != null and tmp2 != null) treAstNewUnion(ctx.mem.?, tmp1, tmp2) else null;
                            } else {
                                node = treAstNewLiteral(ctx.mem.?, wc, wc, ctx.position);
                            }
                            ctx.position += 1;
                            s += @intCast(wlen);
                            break :got_node;
                        }
                        s += 1;
                    },
                }
                // '\\' sub-switch already advanced s by 1 above for most cases
            },
            '.' => {
                if (ctx.cflags & REG_NEWLINE != 0) {
                    const tmp1 = treAstNewLiteral(ctx.mem.?, 0, '\n' - 1, ctx.position);
                    ctx.position += 1;
                    const tmp2 = treAstNewLiteral(ctx.mem.?, '\n' + 1, TRE_CHAR_MAX, ctx.position);
                    ctx.position += 1;
                    node = if (tmp1 != null and tmp2 != null) treAstNewUnion(ctx.mem.?, tmp1, tmp2) else null;
                } else {
                    node = treAstNewLiteral(ctx.mem.?, 0, TRE_CHAR_MAX, ctx.position);
                    ctx.position += 1;
                }
                s += 1;
            },
            '^' => {
                if (ere == 0 and s != ctx.start) {
                    // BRE: treat as literal
                    var wc: wchar_t = 0;
                    const wlen = mbtowc(&wc, s, std.math.maxInt(usize));
                    if (wlen < 0) return REG_BADPAT;
                    node = treAstNewLiteral(ctx.mem.?, wc, wc, ctx.position);
                    ctx.position += 1;
                    s += @intCast(wlen);
                    break :got_node;
                }
                node = treAstNewLiteral(ctx.mem.?, ASSERTION_LIT, ASSERT_AT_BOL, -1);
                s += 1;
            },
            '$' => {
                if (ere == 0 and s[1] != 0 and (s[1] != '\\' or (s[2] != ')' and s[2] != '|'))) {
                    var wc: wchar_t = 0;
                    const wlen = mbtowc(&wc, s, std.math.maxInt(usize));
                    if (wlen < 0) return REG_BADPAT;
                    node = treAstNewLiteral(ctx.mem.?, wc, wc, ctx.position);
                    ctx.position += 1;
                    s += @intCast(wlen);
                    break :got_node;
                }
                node = treAstNewLiteral(ctx.mem.?, ASSERTION_LIT, ASSERT_AT_EOL, -1);
                s += 1;
            },
            '*', '{', '+', '?' => {
                if (ere != 0) return REG_BADRPT;
                // BRE: these are literal chars (same as '|' in BRE → literal)
                var wc: wchar_t = 0;
                const wlen = mbtowc(&wc, s, std.math.maxInt(usize));
                if (wlen < 0) return REG_BADPAT;
                node = treAstNewLiteral(ctx.mem.?, wc, wc, ctx.position);
                ctx.position += 1;
                s += @intCast(wlen);
                break :got_node;
            },
            '|' => {
                if (ere == 0) {
                    // BRE: literal '|'
                    var wc: wchar_t = 0;
                    const wlen = mbtowc(&wc, s, std.math.maxInt(usize));
                    if (wlen < 0) return REG_BADPAT;
                    node = treAstNewLiteral(ctx.mem.?, wc, wc, ctx.position);
                    ctx.position += 1;
                    s += @intCast(wlen);
                    break :got_node;
                }
                // ERE '|': EMPTY
                node = treAstNewLiteral(ctx.mem.?, EMPTY_LIT, -1, -1);
            },
            0 => {
                node = treAstNewLiteral(ctx.mem.?, EMPTY_LIT, -1, -1);
            },
            else => {
                var wc: wchar_t = 0;
                const wlen = mbtowc(&wc, s, std.math.maxInt(usize));
                if (wlen < 0) return REG_BADPAT;
                if (ctx.cflags & REG_ICASE != 0 and
                    (iswupper(@intCast(wc)) != 0 or iswlower(@intCast(wc)) != 0))
                {
                    const tmp1 = treAstNewLiteral(ctx.mem.?, @intCast(towupper(@intCast(wc))), @intCast(towupper(@intCast(wc))), ctx.position);
                    const tmp2 = treAstNewLiteral(ctx.mem.?, @intCast(towlower(@intCast(wc))), @intCast(towlower(@intCast(wc))), ctx.position);
                    node = if (tmp1 != null and tmp2 != null) treAstNewUnion(ctx.mem.?, tmp1, tmp2) else null;
                } else {
                    node = treAstNewLiteral(ctx.mem.?, wc, wc, ctx.position);
                }
                ctx.position += 1;
                s += @intCast(wlen);
                break :got_node;
            },
        }
    } // got_node

    if (node == null) return REG_ESPACE;
    ctx.n = node;
    ctx.s = s;
    return REG_OK;
}

fn treParse(ctx: *TreParseCtx) reg_errcode_t {
    var nbranch: ?*TreAstNode = null;
    var nunion: ?*TreAstNode = null;
    const ere = ctx.cflags & REG_EXTENDED;
    var s: [*]const u8 = ctx.start;
    var subid: c_int = 0;
    var depth: c_int = 0;
    var err: reg_errcode_t = REG_OK;
    const stack = ctx.stack.?;

    err = treStackPushInt(stack, subid);
    subid += 1;
    if (err != REG_OK) return err;

    // Use skip_atom to simulate goto parse_iter
    var skip_atom = false;

    outer: while (true) {
        // Handle opening parenthesis
        if (!skip_atom) {
            if ((ere == 0 and s[0] == '\\' and s[1] == '(') or
                (ere != 0 and s[0] == '('))
            {
                err = treStackPushVoidptr(stack, @ptrCast(nunion));
                if (err != REG_OK) return err;
                err = treStackPushVoidptr(stack, @ptrCast(nbranch));
                if (err != REG_OK) return err;
                err = treStackPushInt(stack, subid);
                if (err != REG_OK) return err;
                subid += 1;
                s += 1;
                if (ere == 0) s += 1;
                depth += 1;
                nbranch = null;
                nunion = null;
                ctx.start = s;
                continue :outer;
            }
        }

        // Parse atom (or use existing ctx.n if skip_atom)
        if (!skip_atom) {
            if ((ere == 0 and s[0] == '\\' and s[1] == ')') or
                (ere != 0 and s[0] == ')' and depth > 0))
            {
                ctx.n = treAstNewLiteral(ctx.mem.?, EMPTY_LIT, -1, -1);
                if (ctx.n == null) return REG_ESPACE;
            } else {
                err = parseAtom(ctx, s);
                if (err != REG_OK) return err;
                s = ctx.s;
            }
        }
        skip_atom = false;

        // parse_iter: process repetition operators
        iter_loop: while (true) {
            var min_rep: c_int = 0;
            var max_rep: c_int = 0;

            // Check for repetition operator
            if (s[0] != '\\' and s[0] != '*') {
                if (ere == 0) break :iter_loop;
                if (s[0] != '+' and s[0] != '?' and s[0] != '{') break :iter_loop;
            }
            if (s[0] == '\\' and ere != 0) break :iter_loop;
            if (s[0] == '\\' and s[1] != '+' and s[1] != '?' and s[1] != '{') break :iter_loop;
            if (s[0] == '\\') s += 1;

            // handle ^* at start of BRE
            const start_plus1 = ctx.start + 1;
            if (ere == 0 and s == start_plus1 and (s - 1)[0] == '^') break :iter_loop;

            if (s[0] == '{') {
                const after = parseDup(s + 1, ere, &min_rep, &max_rep);
                if (after == null) return REG_BADBR;
                s = after.?;
            } else {
                min_rep = 0;
                max_rep = -1;
                if (s[0] == '+') min_rep = 1;
                if (s[0] == '?') max_rep = 1;
                s += 1;
            }
            if (max_rep == 0) {
                ctx.n = treAstNewLiteral(ctx.mem.?, EMPTY_LIT, -1, -1);
            } else {
                ctx.n = treAstNewIter(ctx.mem.?, ctx.n, min_rep, max_rep, 0);
            }
            if (ctx.n == null) return REG_ESPACE;
        }

        nbranch = treAstNewCatenation(ctx.mem.?, nbranch, ctx.n);

        // Check for alternation, group-close, or end
        const is_alt_ere = (ere != 0 and s[0] == '|');
        const is_close_ere = (ere != 0 and s[0] == ')' and depth > 0);
        const is_close_bre = (ere == 0 and s[0] == '\\' and s[1] == ')');
        const is_alt_bre = (ere == 0 and s[0] == '\\' and s[1] == '|');
        const is_end = (s[0] == 0);

        if (is_alt_ere or is_close_ere or is_close_bre or is_alt_bre or is_end) {
            const c = s[0];
            nunion = treAstNewUnion(ctx.mem.?, nunion, nbranch);
            nbranch = null;

            if (c == '\\' and s[1] == '|') {
                s += 2;
                ctx.start = s;
            } else if (c == '|') {
                s += 1;
                ctx.start = s;
            } else {
                if (c == '\\') {
                    if (depth <= 0) return REG_EPAREN;
                    s += 2;
                } else if (c == ')') {
                    s += 1;
                }
                depth -= 1;
                err = marksub(ctx, nunion, treStackPopInt(stack));
                if (err != REG_OK) return err;
                if (c == 0 and depth < 0) {
                    ctx.submatch_id = subid;
                    return REG_OK;
                }
                if (c == 0 or depth < 0) return REG_EPAREN;
                nbranch = @ptrCast(@alignCast(treStackPopVoidptr(stack)));
                nunion = @ptrCast(@alignCast(treStackPopVoidptr(stack)));
                skip_atom = true;
                continue :outer;
            }
        }
    } // outer while
}


// ============================================================
// Tag management
// ============================================================

fn treAddTagLeft(mem: TreMem, node: *TreAstNode, tag_id: c_int) reg_errcode_t {
    const c: *TreCatenation = @ptrCast(@alignCast(treMemAlloc(mem, @sizeOf(TreCatenation)) orelse return REG_ESPACE));
    c.left = treAstNewLiteral(mem, TAG_LIT, tag_id, -1) orelse return REG_ESPACE;
    c.right = @ptrCast(@alignCast(treMemAlloc(mem, @sizeOf(TreAstNode)) orelse return REG_ESPACE));

    const r = c.right.?;
    r.obj = node.obj;
    r.node_type = node.node_type;
    r.nullable = -1;
    r.submatch_id = -1;
    r.firstpos = null;
    r.lastpos = null;
    r.num_tags = 0;
    r.num_submatches = 0;
    node.obj = @ptrCast(c);
    node.node_type = CATENATION;
    return REG_OK;
}

fn treAddTagRight(mem: TreMem, node: *TreAstNode, tag_id: c_int) reg_errcode_t {
    const c: *TreCatenation = @ptrCast(@alignCast(treMemAlloc(mem, @sizeOf(TreCatenation)) orelse return REG_ESPACE));
    c.right = treAstNewLiteral(mem, TAG_LIT, tag_id, -1) orelse return REG_ESPACE;
    c.left = @ptrCast(@alignCast(treMemAlloc(mem, @sizeOf(TreAstNode)) orelse return REG_ESPACE));

    const l = c.left.?;
    l.obj = node.obj;
    l.node_type = node.node_type;
    l.nullable = -1;
    l.submatch_id = -1;
    l.firstpos = null;
    l.lastpos = null;
    l.num_tags = 0;
    l.num_submatches = 0;
    node.obj = @ptrCast(c);
    node.node_type = CATENATION;
    return REG_OK;
}

fn trePurgeRegset(regset: [*]c_int, tnfa: *Tnfa, tag: c_int) void {
    var i: usize = 0;
    while (regset[i] >= 0) : (i += 1) {
        const id = @divTrunc(regset[i], 2);
        const is_start = (@rem(regset[i], 2) == 0);
        if (is_start) {
            tnfa.submatch_data.?[@intCast(id)].so_tag = tag;
        } else {
            tnfa.submatch_data.?[@intCast(id)].eo_tag = tag;
        }
    }
    regset[0] = -1;
}

fn treAddTags(mem_opt: ?TreMem, stack: *TreStack, tree: *TreAstNode, tnfa: *Tnfa) reg_errcode_t {
    var status: reg_errcode_t = REG_OK;
    var node: ?*TreAstNode = tree;
    const bottom = treStackNumObjects(stack);
    const first_pass = (mem_opt == null);
    var num_tags: c_int = 0;
    var num_minimals: c_int = 0;
    var tag: c_int = 0;
    var next_tag: c_int = 1;
    var minimal_tag: c_int = -1;
    var direction: c_int = TRE_TAG_MINIMIZE;

    const num_sub: usize = @intCast(tnfa.num_submatches);
    const regset_buf: [*]c_int = @ptrCast(@alignCast(
        std.c.malloc(@sizeOf(c_int) * ((num_sub + 1) * 2)) orelse return REG_ESPACE,
    ));
    regset_buf[0] = -1;
    var regset: [*]c_int = regset_buf;
    const orig_regset = regset_buf;

    const parents: [*]c_int = @ptrCast(@alignCast(std.c.malloc(@sizeOf(c_int) * (num_sub + 1)) orelse {
        std.c.free(@ptrCast(regset_buf));
        return REG_ESPACE;
    }));
    parents[0] = -1;

    const saved_states: [*]TreTagStates = @ptrCast(@alignCast(std.c.malloc(@sizeOf(TreTagStates) * (num_sub + 1)) orelse {
        std.c.free(@ptrCast(regset_buf));
        std.c.free(@ptrCast(parents));
        return REG_ESPACE;
    }));
    for (0..num_sub + 1) |i| saved_states[i].tag = -1;

    if (!first_pass) {
        tnfa.end_tag = 0;
        tnfa.minimal_tags.?[0] = -1;
    }

    {
        const pv: ?*anyopaque = @ptrCast(node);
        status = treStackPushVoidptr(stack, pv);
        if (status == REG_OK) status = treStackPushInt(stack, ADDTAGS_RECURSE);
    }

    addtags_loop: while (treStackNumObjects(stack) > bottom) {
        if (status != REG_OK) break;

        const addtags_sym1 = treStackPopInt(stack);
        switch (addtags_sym1) {
            ADDTAGS_SET_SUBMATCH_END => {
                const id = treStackPopInt(stack);
                var i: usize = 0;
                while (regset[i] >= 0) : (i += 1) {}
                regset[i] = id * 2 + 1;
                regset[i + 1] = -1;
                i = 0;
                while (parents[i] >= 0) : (i += 1) {}
                if (i > 0) parents[i - 1] = -1;
            },

            ADDTAGS_RECURSE => {
                node = @ptrCast(@alignCast(treStackPopVoidptr(stack)));
                const n = node.?;

                if (n.submatch_id >= 0) {
                    const id = n.submatch_id;
                    var i: usize = 0;
                    while (regset[i] >= 0) : (i += 1) {}
                    regset[i] = id * 2;
                    regset[i + 1] = -1;

                    if (!first_pass) {
                        i = 0;
                        while (parents[i] >= 0) : (i += 1) {}
                        tnfa.submatch_data.?[@intCast(id)].parents = null;
                        if (i > 0) {
                            const p: [*]c_int = @ptrCast(@alignCast(std.c.malloc(@sizeOf(c_int) * (i + 1)) orelse {
                                status = REG_ESPACE;
                                break :addtags_loop;
                            }));
                            tnfa.submatch_data.?[@intCast(id)].parents = p;
                            for (0..i) |j| p[j] = parents[j];
                            p[i] = -1;
                        }
                    }
                    status = treStackPushInt(stack, n.submatch_id);
                    if (status != REG_OK) break :addtags_loop;
                    status = treStackPushInt(stack, ADDTAGS_SET_SUBMATCH_END);
                    if (status != REG_OK) break :addtags_loop;
                }

                switch (n.node_type) {
                    LITERAL => {
                        const lit: *TreLiteral = @ptrCast(@alignCast(n.obj.?));
                        if (!isSpecial(lit) or isBackref(lit)) {
                            if (regset[0] >= 0) {
                                if (!first_pass) {
                                    status = treAddTagLeft(mem_opt.?, n, tag);
                                    tnfa.tag_directions.?[@intCast(tag)] = direction;
                                    if (minimal_tag >= 0) {
                                        var i: usize = 0;
                                        while (tnfa.minimal_tags.?[i] >= 0) : (i += 1) {}
                                        tnfa.minimal_tags.?[i] = tag;
                                        tnfa.minimal_tags.?[i + 1] = minimal_tag;
                                        tnfa.minimal_tags.?[i + 2] = -1;
                                        minimal_tag = -1;
                                        num_minimals += 1;
                                    }
                                    trePurgeRegset(regset, tnfa, tag);
                                } else {
                                    n.num_tags = 1;
                                }
                                regset[0] = -1;
                                tag = next_tag;
                                num_tags += 1;
                                next_tag += 1;
                            }
                        }
                    },
                    CATENATION => {
                        const cat: *TreCatenation = @ptrCast(@alignCast(n.obj.?));
                        const left = cat.left.?;
                        const right = cat.right.?;
                        var reserved_tag: c_int = -1;

                        status = treStackPushVoidptr(stack, @ptrCast(n));
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushInt(stack, ADDTAGS_AFTER_CAT_RIGHT);
                        if (status != REG_OK) break :addtags_loop;

                        status = treStackPushVoidptr(stack, @ptrCast(right));
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushInt(stack, ADDTAGS_RECURSE);
                        if (status != REG_OK) break :addtags_loop;

                        status = treStackPushInt(stack, next_tag + left.num_tags);
                        if (status != REG_OK) break :addtags_loop;
                        if (left.num_tags > 0 and right.num_tags > 0) {
                            reserved_tag = next_tag;
                            next_tag += 1;
                        }
                        status = treStackPushInt(stack, reserved_tag);
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushInt(stack, ADDTAGS_AFTER_CAT_LEFT);
                        if (status != REG_OK) break :addtags_loop;

                        status = treStackPushVoidptr(stack, @ptrCast(left));
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushInt(stack, ADDTAGS_RECURSE);
                        if (status != REG_OK) break :addtags_loop;
                    },
                    ITERATION => {
                        const iter: *TreIteration = @ptrCast(@alignCast(n.obj.?));
                        if (first_pass) {
                            status = treStackPushInt(stack, if (regset[0] >= 0 or iter.minimal != 0) 1 else 0);
                        } else {
                            status = treStackPushInt(stack, tag);
                            if (status == REG_OK) status = treStackPushInt(stack, iter.minimal);
                        }
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushVoidptr(stack, @ptrCast(n));
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushInt(stack, ADDTAGS_AFTER_ITERATION);
                        if (status != REG_OK) break :addtags_loop;

                        status = treStackPushVoidptr(stack, @ptrCast(iter.arg.?));
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushInt(stack, ADDTAGS_RECURSE);
                        if (status != REG_OK) break :addtags_loop;

                        if (regset[0] >= 0 or iter.minimal != 0) {
                            if (!first_pass) {
                                status = treAddTagLeft(mem_opt.?, n, tag);
                                if (iter.minimal != 0) {
                                    tnfa.tag_directions.?[@intCast(tag)] = TRE_TAG_MAXIMIZE;
                                } else {
                                    tnfa.tag_directions.?[@intCast(tag)] = direction;
                                }
                                if (minimal_tag >= 0) {
                                    var i: usize = 0;
                                    while (tnfa.minimal_tags.?[i] >= 0) : (i += 1) {}
                                    tnfa.minimal_tags.?[i] = tag;
                                    tnfa.minimal_tags.?[i + 1] = minimal_tag;
                                    tnfa.minimal_tags.?[i + 2] = -1;
                                    minimal_tag = -1;
                                    num_minimals += 1;
                                }
                                trePurgeRegset(regset, tnfa, tag);
                            }
                            regset[0] = -1;
                            tag = next_tag;
                            num_tags += 1;
                            next_tag += 1;
                        }
                        direction = TRE_TAG_MINIMIZE;
                    },
                    UNION => {
                        const uni: *TreUnion = @ptrCast(@alignCast(n.obj.?));
                        const left = uni.left.?;
                        const right = uni.right.?;
                        var left_tag: c_int = undefined;
                        var right_tag: c_int = undefined;

                        if (regset[0] >= 0) {
                            left_tag = next_tag;
                            right_tag = next_tag + 1;
                        } else {
                            left_tag = tag;
                            right_tag = next_tag;
                        }

                        status = treStackPushInt(stack, right_tag);
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushInt(stack, left_tag);
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushVoidptr(stack, @ptrCast(regset));
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushInt(stack, if (regset[0] >= 0) 1 else 0);
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushVoidptr(stack, @ptrCast(n));
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushVoidptr(stack, @ptrCast(right));
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushVoidptr(stack, @ptrCast(left));
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushInt(stack, ADDTAGS_AFTER_UNION_RIGHT);
                        if (status != REG_OK) break :addtags_loop;

                        status = treStackPushVoidptr(stack, @ptrCast(right));
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushInt(stack, ADDTAGS_RECURSE);
                        if (status != REG_OK) break :addtags_loop;

                        status = treStackPushInt(stack, ADDTAGS_AFTER_UNION_LEFT);
                        if (status != REG_OK) break :addtags_loop;

                        status = treStackPushVoidptr(stack, @ptrCast(left));
                        if (status != REG_OK) break :addtags_loop;
                        status = treStackPushInt(stack, ADDTAGS_RECURSE);
                        if (status != REG_OK) break :addtags_loop;

                        if (regset[0] >= 0) {
                            if (!first_pass) {
                                status = treAddTagLeft(mem_opt.?, n, tag);
                                tnfa.tag_directions.?[@intCast(tag)] = direction;
                                if (minimal_tag >= 0) {
                                    var i: usize = 0;
                                    while (tnfa.minimal_tags.?[i] >= 0) : (i += 1) {}
                                    tnfa.minimal_tags.?[i] = tag;
                                    tnfa.minimal_tags.?[i + 1] = minimal_tag;
                                    tnfa.minimal_tags.?[i + 2] = -1;
                                    minimal_tag = -1;
                                    num_minimals += 1;
                                }
                                trePurgeRegset(regset, tnfa, tag);
                            }
                            regset[0] = -1;
                            tag = next_tag;
                            num_tags += 1;
                            next_tag += 1;
                        }

                        if (n.num_submatches > 0) {
                            next_tag += 1;
                            tag = next_tag;
                            next_tag += 1;
                        }
                    },
                    else => {},
                }

                if (n.submatch_id >= 0) {
                    var i: usize = 0;
                    while (parents[i] >= 0) : (i += 1) {}
                    parents[i] = n.submatch_id;
                    parents[i + 1] = -1;
                }
            },

            ADDTAGS_AFTER_ITERATION => {
                const n: *TreAstNode = @ptrCast(@alignCast(treStackPopVoidptr(stack).?));
                if (first_pass) {
                    const iter: *TreIteration = @ptrCast(@alignCast(n.obj.?));
                    n.num_tags = iter.arg.?.num_tags + treStackPopInt(stack);
                    minimal_tag = -1;
                } else {
                    const min_flag: c_int = treStackPopInt(stack);
                    const enter_tag: c_int = treStackPopInt(stack);
                    if (min_flag != 0) minimal_tag = enter_tag;
                }
                if (!first_pass) {
                    const iter: *TreIteration = @ptrCast(@alignCast(n.obj.?));
                    if (iter.minimal != 0) {
                        direction = TRE_TAG_MINIMIZE;
                    } else {
                        direction = TRE_TAG_MAXIMIZE;
                    }
                }
            },

            ADDTAGS_AFTER_CAT_LEFT => {
                const new_tag_v = treStackPopInt(stack);
                next_tag = treStackPopInt(stack);
                if (new_tag_v >= 0) tag = new_tag_v;
            },

            ADDTAGS_AFTER_CAT_RIGHT => {
                const n: *TreAstNode = @ptrCast(@alignCast(treStackPopVoidptr(stack).?));
                if (first_pass) {
                    const cat: *TreCatenation = @ptrCast(@alignCast(n.obj.?));
                    n.num_tags = cat.left.?.num_tags + cat.right.?.num_tags;
                }
            },

            ADDTAGS_AFTER_UNION_LEFT => {
                while (regset[0] >= 0) regset += 1;
            },

            ADDTAGS_AFTER_UNION_RIGHT => {
                const left: *TreAstNode = @ptrCast(@alignCast(treStackPopVoidptr(stack).?));
                const right: *TreAstNode = @ptrCast(@alignCast(treStackPopVoidptr(stack).?));
                const n: *TreAstNode = @ptrCast(@alignCast(treStackPopVoidptr(stack).?));
                const added_tags = treStackPopInt(stack);
                if (first_pass) {
                    const uni: *TreUnion = @ptrCast(@alignCast(n.obj.?));
                    n.num_tags = uni.left.?.num_tags + uni.right.?.num_tags + added_tags +
                        (if (n.num_submatches > 0) @as(c_int, 2) else 0);
                }
                regset = @ptrCast(@alignCast(treStackPopVoidptr(stack).?));
                const tag_left = treStackPopInt(stack);
                const tag_right = treStackPopInt(stack);

                if (n.num_submatches > 0) {
                    if (!first_pass) {
                        status = treAddTagRight(mem_opt.?, left, tag_left);
                        tnfa.tag_directions.?[@intCast(tag_left)] = TRE_TAG_MAXIMIZE;
                        if (status == REG_OK) {
                            status = treAddTagRight(mem_opt.?, right, tag_right);
                            tnfa.tag_directions.?[@intCast(tag_right)] = TRE_TAG_MAXIMIZE;
                        }
                    }
                    num_tags += 2;
                }
                direction = TRE_TAG_MAXIMIZE;
            },

            else => {},
        }
    }

    if (!first_pass) trePurgeRegset(regset, tnfa, tag);
    if (!first_pass and minimal_tag >= 0) {
        var i: usize = 0;
        while (tnfa.minimal_tags.?[i] >= 0) : (i += 1) {}
        tnfa.minimal_tags.?[i] = tag;
        tnfa.minimal_tags.?[i + 1] = minimal_tag;
        tnfa.minimal_tags.?[i + 2] = -1;
        num_minimals += 1;
    }

    tnfa.end_tag = num_tags;
    tnfa.num_tags = num_tags;
    tnfa.num_minimals = num_minimals;
    std.c.free(@ptrCast(orig_regset));
    std.c.free(@ptrCast(parents));
    std.c.free(@ptrCast(saved_states));
    return status;
}


// ============================================================
// AST copying and expansion
// ============================================================

fn treCopyAst(
    mem: TreMem,
    stack: *TreStack,
    ast: *TreAstNode,
    flags: c_int,
    pos_add: *c_int,
    tag_directions: ?[*]c_int,
    copy_out: *?*TreAstNode,
    max_pos: *c_int,
) reg_errcode_t {
    var status: reg_errcode_t = REG_OK;
    const bottom = treStackNumObjects(stack);
    var num_copied: c_int = 0;
    var first_tag: c_int = 1;
    var result: *?*TreAstNode = copy_out;

    {
        var _s = treStackPushVoidptr(stack, @ptrCast(ast));
        if (_s == REG_OK) _s = treStackPushInt(stack, COPY_RECURSE);
        if (_s != REG_OK) return _s;
    }

    copy_loop: while (status == REG_OK and treStackNumObjects(stack) > bottom) {
        const addtags_sym2 = treStackPopInt(stack);
        switch (addtags_sym2) {
            COPY_SET_RESULT_PTR => {
                result = @ptrCast(@alignCast(treStackPopVoidptr(stack).?));
            },
            COPY_RECURSE => {
                const nd: *TreAstNode = @ptrCast(@alignCast(treStackPopVoidptr(stack).?));
                switch (nd.node_type) {
                    LITERAL => {
                        const lit: *TreLiteral = @ptrCast(@alignCast(nd.obj.?));
                        var pos = lit.position;
                        var min_c = lit.code_min;
                        var max_c = lit.code_max;
                        if (!isSpecial(lit) or isBackref(lit)) {
                            pos += pos_add.*;
                            num_copied += 1;
                        } else if (isTag(lit) and (flags & COPY_REMOVE_TAGS != 0)) {
                            min_c = EMPTY_LIT;
                            max_c = -1;
                            pos = -1;
                        } else if (isTag(lit) and (flags & COPY_MAXIMIZE_FIRST_TAG != 0) and first_tag != 0) {
                            if (tag_directions) |td| td[@intCast(max_c)] = TRE_TAG_MAXIMIZE;
                            first_tag = 0;
                        }
                        result.* = treAstNewLiteral(mem, @intCast(min_c), @intCast(max_c), @intCast(pos));
                        if (result.* == null) {
                            status = REG_ESPACE;
                        } else {
                            const p: *TreLiteral = @ptrCast(@alignCast(result.*.?.obj.?));
                            p.char_class = lit.char_class;
                            p.neg_classes = lit.neg_classes;
                        }
                        if (pos > max_pos.*) max_pos.* = pos;
                    },
                    UNION => {
                        const uni: *TreUnion = @ptrCast(@alignCast(nd.obj.?));
                        result.* = treAstNewUnion(mem, uni.left, uni.right);
                        if (result.* == null) {
                            status = REG_ESPACE;
                            break :copy_loop;
                        }
                        const tmp: *TreUnion = @ptrCast(@alignCast(result.*.?.obj.?));
                        result = &tmp.left;
                        status = treStackPushVoidptr(stack, @ptrCast(uni.right));
                        if (status != REG_OK) break :copy_loop;
                        status = treStackPushInt(stack, COPY_RECURSE);
                        if (status != REG_OK) break :copy_loop;
                        status = treStackPushVoidptr(stack, @ptrCast(&tmp.right));
                        if (status != REG_OK) break :copy_loop;
                        status = treStackPushInt(stack, COPY_SET_RESULT_PTR);
                        if (status != REG_OK) break :copy_loop;
                        status = treStackPushVoidptr(stack, @ptrCast(uni.left));
                        if (status != REG_OK) break :copy_loop;
                        status = treStackPushInt(stack, COPY_RECURSE);
                        if (status != REG_OK) break :copy_loop;
                    },
                    CATENATION => {
                        const cat: *TreCatenation = @ptrCast(@alignCast(nd.obj.?));
                        result.* = treAstNewCatenation(mem, cat.left, cat.right);
                        if (result.* == null) {
                            status = REG_ESPACE;
                            break :copy_loop;
                        }
                        const tmp: *TreCatenation = @ptrCast(@alignCast(result.*.?.obj.?));
                        tmp.left = null;
                        tmp.right = null;
                        result = &tmp.left;
                        status = treStackPushVoidptr(stack, @ptrCast(cat.right));
                        if (status != REG_OK) break :copy_loop;
                        status = treStackPushInt(stack, COPY_RECURSE);
                        if (status != REG_OK) break :copy_loop;
                        status = treStackPushVoidptr(stack, @ptrCast(&tmp.right));
                        if (status != REG_OK) break :copy_loop;
                        status = treStackPushInt(stack, COPY_SET_RESULT_PTR);
                        if (status != REG_OK) break :copy_loop;
                        status = treStackPushVoidptr(stack, @ptrCast(cat.left));
                        if (status != REG_OK) break :copy_loop;
                        status = treStackPushInt(stack, COPY_RECURSE);
                        if (status != REG_OK) break :copy_loop;
                    },
                    ITERATION => {
                        const iter: *TreIteration = @ptrCast(@alignCast(nd.obj.?));
                        status = treStackPushVoidptr(stack, @ptrCast(iter.arg.?));
                        if (status != REG_OK) break :copy_loop;
                        status = treStackPushInt(stack, COPY_RECURSE);
                        if (status != REG_OK) break :copy_loop;
                        result.* = treAstNewIter(mem, iter.arg, iter.min, iter.max, iter.minimal);
                        if (result.* == null) {
                            status = REG_ESPACE;
                            break :copy_loop;
                        }
                        const new_iter: *TreIteration = @ptrCast(@alignCast(result.*.?.obj.?));
                        result = &new_iter.arg;
                    },
                    else => {},
                }
            },
            else => {},
        }
    }
    pos_add.* += num_copied;
    return status;
}

fn treExpandAst(
    mem: TreMem,
    stack: *TreStack,
    ast: *TreAstNode,
    position: *c_int,
    tag_directions: ?[*]c_int,
) reg_errcode_t {
    var status: reg_errcode_t = REG_OK;
    const bottom = treStackNumObjects(stack);
    var pos_add: c_int = 0;
    var pos_add_total: c_int = 0;
    var max_pos: c_int = 0;
    var iter_depth: c_int = 0;

    {
        var _s = treStackPushVoidptr(stack, @ptrCast(ast));
        if (_s == REG_OK) _s = treStackPushInt(stack, EXPAND_RECURSE);
        if (_s != REG_OK) return _s;
    }

    while (status == REG_OK and treStackNumObjects(stack) > bottom) {
        const addtags_sym3 = treStackPopInt(stack);
        const nd: *TreAstNode = @ptrCast(@alignCast(treStackPopVoidptr(stack).?));

        switch (addtags_sym3) {
            EXPAND_RECURSE => {
                switch (nd.node_type) {
                    LITERAL => {
                        const lit: *TreLiteral = @ptrCast(@alignCast(nd.obj.?));
                        if (!isSpecial(lit) or isBackref(lit)) {
                            lit.position += pos_add;
                            if (lit.position > max_pos) max_pos = @intCast(lit.position);
                        }
                    },
                    UNION => {
                        const uni: *TreUnion = @ptrCast(@alignCast(nd.obj.?));
                        status = treStackPushVoidptr(stack, @ptrCast(uni.right));
                        if (status == REG_OK) status = treStackPushInt(stack, EXPAND_RECURSE);
                        if (status == REG_OK) status = treStackPushVoidptr(stack, @ptrCast(uni.left));
                        if (status == REG_OK) status = treStackPushInt(stack, EXPAND_RECURSE);
                    },
                    CATENATION => {
                        const cat: *TreCatenation = @ptrCast(@alignCast(nd.obj.?));
                        status = treStackPushVoidptr(stack, @ptrCast(cat.right));
                        if (status == REG_OK) status = treStackPushInt(stack, EXPAND_RECURSE);
                        if (status == REG_OK) status = treStackPushVoidptr(stack, @ptrCast(cat.left));
                        if (status == REG_OK) status = treStackPushInt(stack, EXPAND_RECURSE);
                    },
                    ITERATION => {
                        const iter: *TreIteration = @ptrCast(@alignCast(nd.obj.?));
                        status = treStackPushInt(stack, pos_add);
                        if (status == REG_OK) status = treStackPushVoidptr(stack, @ptrCast(nd));
                        if (status == REG_OK) status = treStackPushInt(stack, EXPAND_AFTER_ITER);
                        if (status == REG_OK) status = treStackPushVoidptr(stack, @ptrCast(iter.arg.?));
                        if (status == REG_OK) status = treStackPushInt(stack, EXPAND_RECURSE);
                        if (iter.min > 1 or iter.max > 1) pos_add = 0;
                        iter_depth += 1;
                    },
                    else => {},
                }
            },
            EXPAND_AFTER_ITER => {
                const iter: *TreIteration = @ptrCast(@alignCast(nd.obj.?));
                const pos_add_last = pos_add;
                pos_add = treStackPopInt(stack);
                if (iter.min > 1 or iter.max > 1) {
                    var seq1: ?*TreAstNode = null;
                    var seq2: ?*TreAstNode = null;
                    var pos_add_save = pos_add;

                    var j: c_int = 0;
                    while (j < iter.min) : (j += 1) {
                        var copy: ?*TreAstNode = null;
                        const fl: c_int = if (j + 1 < iter.min) COPY_REMOVE_TAGS else COPY_MAXIMIZE_FIRST_TAG;
                        pos_add_save = pos_add;
                        status = treCopyAst(mem, stack, iter.arg.?, fl, &pos_add, tag_directions, &copy, &max_pos);
                        if (status != REG_OK) return status;
                        if (seq1 != null) {
                            seq1 = treAstNewCatenation(mem, seq1, copy);
                        } else {
                            seq1 = copy;
                        }
                        if (seq1 == null) return REG_ESPACE;
                    }

                    if (iter.max == -1) {
                        pos_add_save = pos_add;
                        status = treCopyAst(mem, stack, iter.arg.?, 0, &pos_add, null, &seq2, &max_pos);
                        if (status != REG_OK) return status;
                        seq2 = treAstNewIter(mem, seq2, 0, -1, 0);
                        if (seq2 == null) return REG_ESPACE;
                    } else {
                        j = iter.min;
                        while (j < iter.max) : (j += 1) {
                            var copy: ?*TreAstNode = null;
                            pos_add_save = pos_add;
                            status = treCopyAst(mem, stack, iter.arg.?, 0, &pos_add, null, &copy, &max_pos);
                            if (status != REG_OK) return status;
                            if (seq2 != null) {
                                seq2 = treAstNewCatenation(mem, copy, seq2);
                            } else {
                                seq2 = copy;
                            }
                            if (seq2 == null) return REG_ESPACE;
                            const tmp = treAstNewLiteral(mem, EMPTY_LIT, -1, -1);
                            if (tmp == null) return REG_ESPACE;
                            seq2 = treAstNewUnion(mem, tmp, seq2);
                            if (seq2 == null) return REG_ESPACE;
                        }
                    }

                    pos_add = pos_add_save;
                    if (seq1 == null) {
                        seq1 = seq2;
                    } else if (seq2 != null) {
                        seq1 = treAstNewCatenation(mem, seq1, seq2);
                    }
                    if (seq1 == null) return REG_ESPACE;
                    nd.obj = seq1.?.obj;
                    nd.node_type = seq1.?.node_type;
                }
                iter_depth -= 1;
                pos_add_total += pos_add - pos_add_last;
                if (iter_depth == 0) pos_add = pos_add_total;
            },
            else => {},
        }
    }

    position.* += pos_add_total;
    if (max_pos > position.*) position.* = max_pos;
    return status;
}

// ============================================================
// NFL computation
// ============================================================

fn treSetEmpty(mem: TreMem) ?[*]TrePosAndTags {
    const new_set: [*]TrePosAndTags = @ptrCast(@alignCast(
        treMemCalloc(mem, @sizeOf(TrePosAndTags)) orelse return null,
    ));
    new_set[0].position = -1;
    new_set[0].code_min = -1;
    new_set[0].code_max = -1;
    return new_set;
}

fn treSetOne(
    mem: TreMem,
    position: c_int,
    code_min: c_int,
    code_max: c_int,
    char_class: wctype_t,
    neg_classes: ?[*]wctype_t,
    backref: c_int,
) ?[*]TrePosAndTags {
    const new_set: [*]TrePosAndTags = @ptrCast(@alignCast(
        treMemCalloc(mem, @sizeOf(TrePosAndTags) * 2) orelse return null,
    ));
    new_set[0].position = position;
    new_set[0].code_min = code_min;
    new_set[0].code_max = code_max;
    new_set[0].char_class = char_class;
    new_set[0].neg_classes = neg_classes;
    new_set[0].backref = backref;
    new_set[1].position = -1;
    new_set[1].code_min = -1;
    new_set[1].code_max = -1;
    return new_set;
}

fn treSetUnion(
    mem: TreMem,
    set1: [*]TrePosAndTags,
    set2: [*]TrePosAndTags,
    tags: ?[*]c_int,
    assertions: c_int,
) ?[*]TrePosAndTags {
    var num_tags: usize = 0;
    while (tags != null and tags.?[num_tags] >= 0) : (num_tags += 1) {}
    var s1: usize = 0;
    while (set1[s1].position >= 0) : (s1 += 1) {}
    var s2: usize = 0;
    while (set2[s2].position >= 0) : (s2 += 1) {}
    const new_set: [*]TrePosAndTags = @ptrCast(@alignCast(
        treMemCalloc(mem, @sizeOf(TrePosAndTags) * (s1 + s2 + 1)) orelse return null,
    ));

    s1 = 0;
    while (set1[s1].position >= 0) : (s1 += 1) {
        new_set[s1] = set1[s1];
        new_set[s1].assertions |= assertions;
        if (set1[s1].tags == null and tags == null) {
            new_set[s1].tags = null;
        } else {
            var i: usize = 0;
            while (set1[s1].tags != null and set1[s1].tags.?[i] >= 0) : (i += 1) {}
            const new_tags: [*]c_int = @ptrCast(@alignCast(
                treMemAlloc(mem, @sizeOf(c_int) * (i + num_tags + 1)) orelse return null,
            ));
            for (0..i) |j| new_tags[j] = set1[s1].tags.?[j];
            for (0..num_tags) |j| new_tags[i + j] = tags.?[j];
            new_tags[i + num_tags] = -1;
            new_set[s1].tags = new_tags;
        }
    }

    s2 = 0;
    while (set2[s2].position >= 0) : (s2 += 1) {
        new_set[s1 + s2] = set2[s2];
        if (set2[s2].tags != null) {
            var i: usize = 0;
            while (set2[s2].tags.?[i] >= 0) : (i += 1) {}
            const new_tags: [*]c_int = @ptrCast(@alignCast(
                treMemAlloc(mem, @sizeOf(c_int) * (i + 1)) orelse return null,
            ));
            for (0..i) |j| new_tags[j] = set2[s2].tags.?[j];
            new_tags[i] = -1;
            new_set[s1 + s2].tags = new_tags;
        }
    }
    new_set[s1 + s2].position = -1;
    return new_set;
}

fn treMatchEmpty(
    stack: *TreStack,
    node: *TreAstNode,
    tags: ?[*]c_int,
    assertions: ?*c_int,
    num_tags_seen: ?*c_int,
) reg_errcode_t {
    const bottom = treStackNumObjects(stack);
    var status: reg_errcode_t = REG_OK;
    if (num_tags_seen) |n| n.* = 0;

    status = treStackPushVoidptr(stack, @ptrCast(node));
    if (status != REG_OK) return status;

    while (status == REG_OK and treStackNumObjects(stack) > bottom) {
        const nd: *TreAstNode = @ptrCast(@alignCast(treStackPopVoidptr(stack).?));
        switch (nd.node_type) {
            LITERAL => {
                const lit: *TreLiteral = @ptrCast(@alignCast(nd.obj.?));
                switch (lit.code_min) {
                    TAG_LIT => {
                        if (lit.code_max >= 0) {
                            if (tags) |t| {
                                var i: usize = 0;
                                while (t[i] >= 0) : (i += 1) {
                                    if (t[i] == @as(c_int, @intCast(lit.code_max))) break;
                                }
                                if (t[i] < 0) {
                                    t[i] = @intCast(lit.code_max);
                                    t[i + 1] = -1;
                                }
                            }
                            if (num_tags_seen) |n| n.* += 1;
                        }
                    },
                    ASSERTION_LIT => {
                        if (assertions) |a| a.* |= @intCast(lit.code_max);
                    },
                    EMPTY_LIT => {},
                    else => {},
                }
            },
            UNION => {
                const uni: *TreUnion = @ptrCast(@alignCast(nd.obj.?));
                if (uni.left.?.nullable != 0) {
                    status = treStackPushVoidptr(stack, @ptrCast(uni.left.?));
                } else if (uni.right.?.nullable != 0) {
                    status = treStackPushVoidptr(stack, @ptrCast(uni.right.?));
                }
            },
            CATENATION => {
                const cat: *TreCatenation = @ptrCast(@alignCast(nd.obj.?));
                status = treStackPushVoidptr(stack, @ptrCast(cat.left.?));
                if (status == REG_OK) status = treStackPushVoidptr(stack, @ptrCast(cat.right.?));
            },
            ITERATION => {
                const iter: *TreIteration = @ptrCast(@alignCast(nd.obj.?));
                if (iter.arg.?.nullable != 0) {
                    status = treStackPushVoidptr(stack, @ptrCast(iter.arg.?));
                }
            },
            else => {},
        }
    }
    return status;
}

fn treComputeNfl(mem: TreMem, stack: *TreStack, tree: *TreAstNode) reg_errcode_t {
    const bottom = treStackNumObjects(stack);
    {
        var _s = treStackPushVoidptr(stack, @ptrCast(tree));
        if (_s == REG_OK) _s = treStackPushInt(stack, NFL_RECURSE);
        if (_s != REG_OK) return _s;
    }

    while (treStackNumObjects(stack) > bottom) {
        const addtags_sym4 = treStackPopInt(stack);
        const nd: *TreAstNode = @ptrCast(@alignCast(treStackPopVoidptr(stack).?));

        switch (addtags_sym4) {
            NFL_RECURSE => {
                switch (nd.node_type) {
                    LITERAL => {
                        const lit: *TreLiteral = @ptrCast(@alignCast(nd.obj.?));
                        if (isBackref(lit)) {
                            nd.nullable = 0;
                            nd.firstpos = treSetOne(mem, lit.position, 0, TRE_CHAR_MAX, 0, null, -1);
                            if (nd.firstpos == null) return REG_ESPACE;
                            nd.lastpos = treSetOne(mem, lit.position, 0, TRE_CHAR_MAX, 0, null, @intCast(lit.code_max));
                            if (nd.lastpos == null) return REG_ESPACE;
                        } else if (lit.code_min < 0) {
                            nd.nullable = 1;
                            nd.firstpos = treSetEmpty(mem);
                            if (nd.firstpos == null) return REG_ESPACE;
                            nd.lastpos = treSetEmpty(mem);
                            if (nd.lastpos == null) return REG_ESPACE;
                        } else {
                            nd.nullable = 0;
                            nd.firstpos = treSetOne(mem, lit.position, @intCast(lit.code_min), @intCast(lit.code_max), 0, null, -1);
                            if (nd.firstpos == null) return REG_ESPACE;
                            nd.lastpos = treSetOne(mem, lit.position, @intCast(lit.code_min), @intCast(lit.code_max), lit.char_class, lit.neg_classes, -1);
                            if (nd.lastpos == null) return REG_ESPACE;
                        }
                    },
                    UNION => {
                        var _s = treStackPushVoidptr(stack, @ptrCast(nd));
                        if (_s == REG_OK) _s = treStackPushInt(stack, NFL_POST_UNION);
                        const uni: *TreUnion = @ptrCast(@alignCast(nd.obj.?));
                        if (_s == REG_OK) _s = treStackPushVoidptr(stack, @ptrCast(uni.right.?));
                        if (_s == REG_OK) _s = treStackPushInt(stack, NFL_RECURSE);
                        if (_s == REG_OK) _s = treStackPushVoidptr(stack, @ptrCast(uni.left.?));
                        if (_s == REG_OK) _s = treStackPushInt(stack, NFL_RECURSE);
                        if (_s != REG_OK) return _s;
                    },
                    CATENATION => {
                        var _s = treStackPushVoidptr(stack, @ptrCast(nd));
                        if (_s == REG_OK) _s = treStackPushInt(stack, NFL_POST_CATENATION);
                        const cat: *TreCatenation = @ptrCast(@alignCast(nd.obj.?));
                        if (_s == REG_OK) _s = treStackPushVoidptr(stack, @ptrCast(cat.right.?));
                        if (_s == REG_OK) _s = treStackPushInt(stack, NFL_RECURSE);
                        if (_s == REG_OK) _s = treStackPushVoidptr(stack, @ptrCast(cat.left.?));
                        if (_s == REG_OK) _s = treStackPushInt(stack, NFL_RECURSE);
                        if (_s != REG_OK) return _s;
                    },
                    ITERATION => {
                        var _s = treStackPushVoidptr(stack, @ptrCast(nd));
                        if (_s == REG_OK) _s = treStackPushInt(stack, NFL_POST_ITERATION);
                        const iter: *TreIteration = @ptrCast(@alignCast(nd.obj.?));
                        if (_s == REG_OK) _s = treStackPushVoidptr(stack, @ptrCast(iter.arg.?));
                        if (_s == REG_OK) _s = treStackPushInt(stack, NFL_RECURSE);
                        if (_s != REG_OK) return _s;
                    },
                    else => {},
                }
            },
            NFL_POST_UNION => {
                const uni: *TreUnion = @ptrCast(@alignCast(nd.obj.?));
                nd.nullable = if (uni.left.?.nullable != 0 or uni.right.?.nullable != 0) 1 else 0;
                nd.firstpos = treSetUnion(mem, uni.left.?.firstpos.?, uni.right.?.firstpos.?, null, 0);
                if (nd.firstpos == null) return REG_ESPACE;
                nd.lastpos = treSetUnion(mem, uni.left.?.lastpos.?, uni.right.?.lastpos.?, null, 0);
                if (nd.lastpos == null) return REG_ESPACE;
            },
            NFL_POST_ITERATION => {
                const iter: *TreIteration = @ptrCast(@alignCast(nd.obj.?));
                nd.nullable = if (iter.min == 0 or iter.arg.?.nullable != 0) 1 else 0;
                nd.firstpos = iter.arg.?.firstpos;
                nd.lastpos = iter.arg.?.lastpos;
            },
            NFL_POST_CATENATION => {
                const cat: *TreCatenation = @ptrCast(@alignCast(nd.obj.?));
                nd.nullable = if (cat.left.?.nullable != 0 and cat.right.?.nullable != 0) 1 else 0;

                if (cat.left.?.nullable != 0) {
                    var num_t: c_int = 0;
                    var st = treMatchEmpty(stack, cat.left.?, null, null, &num_t);
                    if (st != REG_OK) return st;
                    const ftags: [*]c_int = @ptrCast(@alignCast(std.c.malloc(@sizeOf(c_int) * @as(usize, @intCast(num_t + 1))) orelse return REG_ESPACE));
                    ftags[0] = -1;
                    var fassertion: c_int = 0;
                    st = treMatchEmpty(stack, cat.left.?, ftags, &fassertion, null);
                    if (st != REG_OK) { std.c.free(@ptrCast(ftags)); return st; }
                    nd.firstpos = treSetUnion(mem, cat.right.?.firstpos.?, cat.left.?.firstpos.?, ftags, fassertion);
                    std.c.free(@ptrCast(ftags));
                    if (nd.firstpos == null) return REG_ESPACE;
                } else {
                    nd.firstpos = cat.left.?.firstpos;
                }

                if (cat.right.?.nullable != 0) {
                    var num_t: c_int = 0;
                    var st = treMatchEmpty(stack, cat.right.?, null, null, &num_t);
                    if (st != REG_OK) return st;
                    const ltags: [*]c_int = @ptrCast(@alignCast(std.c.malloc(@sizeOf(c_int) * @as(usize, @intCast(num_t + 1))) orelse return REG_ESPACE));
                    ltags[0] = -1;
                    var lassertion: c_int = 0;
                    st = treMatchEmpty(stack, cat.right.?, ltags, &lassertion, null);
                    if (st != REG_OK) { std.c.free(@ptrCast(ltags)); return st; }
                    nd.lastpos = treSetUnion(mem, cat.left.?.lastpos.?, cat.right.?.lastpos.?, ltags, lassertion);
                    std.c.free(@ptrCast(ltags));
                    if (nd.lastpos == null) return REG_ESPACE;
                } else {
                    nd.lastpos = cat.right.?.lastpos;
                }
            },
            else => {},
        }
    }
    return REG_OK;
}

// ============================================================
// TNFA construction
// ============================================================

fn treMakeTrans(
    p1: [*]TrePosAndTags,
    p2_in: [*]TrePosAndTags,
    transitions: ?[*]TnfaTransition,
    counts: ?[*]c_int,
    offs: ?[*]c_int,
) reg_errcode_t {
    const orig_p2 = p2_in;

    if (transitions) |trans_arr| {
        var pp1 = p1;
        while (pp1[0].position >= 0) : (pp1 += 1) {
            var p2 = orig_p2;
            var prev_p2_pos: c_int = -1;
            while (p2[0].position >= 0) : (p2 += 1) {
                if (p2[0].position == prev_p2_pos) continue;
                prev_p2_pos = p2[0].position;

                var trans = trans_arr + @as(usize, @intCast(offs.?[@intCast(pp1[0].position)]));
                while (trans[0].state != null) : (trans += 1) {}

                if (trans[0].state == null) (trans + 1)[0].state = null;

                trans[0].code_min = @intCast(pp1[0].code_min);
                trans[0].code_max = @intCast(pp1[0].code_max);
                trans[0].state = @ptrCast(trans_arr + @as(usize, @intCast(offs.?[@intCast(p2[0].position)])));
                trans[0].state_id = p2[0].position;
                trans[0].assertions = pp1[0].assertions | p2[0].assertions |
                    (if (pp1[0].char_class != 0) ASSERT_CHAR_CLASS else 0) |
                    (if (pp1[0].neg_classes != null) ASSERT_CHAR_CLASS_NEG else 0);

                if (pp1[0].backref >= 0) {
                    trans[0].u.backref = pp1[0].backref;
                    trans[0].assertions |= ASSERT_BACKREF;
                } else {
                    trans[0].u.char_class = pp1[0].char_class;
                }

                if (pp1[0].neg_classes) |nc| {
                    var ni: usize = 0;
                    while (nc[ni] != 0) : (ni += 1) {}
                    trans[0].neg_classes = @ptrCast(@alignCast(std.c.malloc(@sizeOf(wctype_t) * (ni + 1)) orelse return REG_ESPACE));
                    for (0..ni) |nj| trans[0].neg_classes.?[nj] = nc[nj];
                    trans[0].neg_classes.?[ni] = 0;
                } else {
                    trans[0].neg_classes = null;
                }

                var ti: usize = 0;
                if (pp1[0].tags) |pt| { while (pt[ti] >= 0) : (ti += 1) {} }
                var tj: usize = 0;
                if (p2[0].tags) |pt| { while (pt[tj] >= 0) : (tj += 1) {} }

                if (trans[0].tags) |t| std.c.free(@ptrCast(t));
                trans[0].tags = null;

                if (ti + tj > 0) {
                    const new_tags: [*]c_int = @ptrCast(@alignCast(std.c.malloc(@sizeOf(c_int) * (ti + tj + 1)) orelse return REG_ESPACE));
                    var tk: usize = 0;
                    if (pp1[0].tags) |pt| while (pt[tk] >= 0) : (tk += 1) {
                        new_tags[tk] = pt[tk];
                    };
                    var tl = tk;
                    var tj2: usize = 0;
                    if (p2[0].tags) |pt| while (pt[tj2] >= 0) : (tj2 += 1) {
                        var dup = false;
                        for (0..tk) |k| if (new_tags[k] == pt[tj2]) { dup = true; break; };
                        if (!dup) {
                            new_tags[tl] = pt[tj2];
                            tl += 1;
                        }
                    };
                    new_tags[tl] = -1;
                    trans[0].tags = new_tags;
                }
            }
        }
    } else if (counts) |cnt| {
        var pp1 = p1;
        while (pp1[0].position >= 0) : (pp1 += 1) {
            var p2 = orig_p2;
            while (p2[0].position >= 0) : (p2 += 1) {
                cnt[@intCast(pp1[0].position)] += 1;
            }
        }
    }
    return REG_OK;
}

fn treAstToTnfa(
    node: *TreAstNode,
    transitions: ?[*]TnfaTransition,
    counts: ?[*]c_int,
    offs: ?[*]c_int,
) reg_errcode_t {
    switch (node.node_type) {
        LITERAL => {},
        UNION => {
            const uni: *TreUnion = @ptrCast(@alignCast(node.obj.?));
            var ec = treAstToTnfa(uni.left.?, transitions, counts, offs);
            if (ec != REG_OK) return ec;
            ec = treAstToTnfa(uni.right.?, transitions, counts, offs);
            return ec;
        },
        CATENATION => {
            const cat: *TreCatenation = @ptrCast(@alignCast(node.obj.?));
            var ec = treMakeTrans(cat.left.?.lastpos.?, cat.right.?.firstpos.?, transitions, counts, offs);
            if (ec != REG_OK) return ec;
            ec = treAstToTnfa(cat.left.?, transitions, counts, offs);
            if (ec != REG_OK) return ec;
            ec = treAstToTnfa(cat.right.?, transitions, counts, offs);
            return ec;
        },
        ITERATION => {
            const iter: *TreIteration = @ptrCast(@alignCast(node.obj.?));
            if (iter.max == -1) {
                const ec = treMakeTrans(iter.arg.?.lastpos.?, iter.arg.?.firstpos.?, transitions, counts, offs);
                if (ec != REG_OK) return ec;
            }
            return treAstToTnfa(iter.arg.?, transitions, counts, offs);
        },
        else => {},
    }
    return REG_OK;
}


// ============================================================
// regcomp / regfree
// ============================================================

fn regcompImpl(preg: *regex_t, regex_pat: [*:0]const u8, cflags: c_int) callconv(.c) c_int {
    var stack: ?*TreStack = null;
    var mem: ?TreMem = null;
    var tnfa: ?*Tnfa = null;
    var counts: ?[*]c_int = null;
    var offs: ?[*]c_int = null;
    var tag_directions: ?[*]c_int = null;

    var errcode: reg_errcode_t = REG_OK;

    error_block: {
        stack = treStackNew(512, 1024000, 128) orelse {
            errcode = REG_ESPACE;
            break :error_block;
        };
        mem = treMemNew() orelse {
            errcode = REG_ESPACE;
            break :error_block;
        };

        var parse_ctx = TreParseCtx{
            .mem = mem,
            .stack = stack,
            .n = null,
            .s = regex_pat,
            .start = regex_pat,
            .submatch_id = 0,
            .position = 0,
            .max_backref = -1,
            .cflags = cflags,
        };

        errcode = treParse(&parse_ctx);
        if (errcode != REG_OK) break :error_block;

        preg.re_nsub = @intCast(parse_ctx.submatch_id - 1);
        const tree = parse_ctx.n orelse {
            errcode = REG_ESPACE;
            break :error_block;
        };

        if (parse_ctx.max_backref > @as(c_int, @intCast(preg.re_nsub))) {
            errcode = REG_ESUBREG;
            break :error_block;
        }

        tnfa = @ptrCast(@alignCast(std.c.calloc(1, @sizeOf(Tnfa)) orelse {
            errcode = REG_ESPACE;
            break :error_block;
        }));
        tnfa.?.have_backrefs = if (parse_ctx.max_backref >= 0) 1 else 0;
        tnfa.?.have_approx = 0;
        tnfa.?.num_submatches = @intCast(parse_ctx.submatch_id);

        if (tnfa.?.have_backrefs != 0 or cflags & REG_NOSUB == 0) {
            errcode = treAddTags(null, stack.?, tree, tnfa.?);
            if (errcode != REG_OK) break :error_block;

            if (tnfa.?.num_tags > 0) {
                tag_directions = @ptrCast(@alignCast(std.c.malloc(
                    @sizeOf(c_int) * @as(usize, @intCast(tnfa.?.num_tags + 1)),
                ) orelse {
                    errcode = REG_ESPACE;
                    break :error_block;
                }));
                tnfa.?.tag_directions = tag_directions;
                _ = memset(@ptrCast(tag_directions.?), -1, @sizeOf(c_int) * @as(usize, @intCast(tnfa.?.num_tags + 1)));
            }

            tnfa.?.minimal_tags = @ptrCast(@alignCast(std.c.calloc(
                @as(usize, @intCast(tnfa.?.num_tags)) * 2 + 1,
                @sizeOf(c_int),
            ) orelse {
                errcode = REG_ESPACE;
                break :error_block;
            }));

            const submatch_data: [*]TreSubmatchData = @ptrCast(@alignCast(std.c.calloc(
                @intCast(parse_ctx.submatch_id),
                @sizeOf(TreSubmatchData),
            ) orelse {
                errcode = REG_ESPACE;
                break :error_block;
            }));
            tnfa.?.submatch_data = submatch_data;

            errcode = treAddTags(mem.?, stack.?, tree, tnfa.?);
            if (errcode != REG_OK) break :error_block;
        }

        errcode = treExpandAst(mem.?, stack.?, tree, &parse_ctx.position, tag_directions);
        if (errcode != REG_OK) break :error_block;

        const tmp_ast_l = tree;
        const tmp_ast_r = treAstNewLiteral(mem.?, 0, 0, parse_ctx.position) orelse {
            errcode = REG_ESPACE;
            break :error_block;
        };
        parse_ctx.position += 1;

        const full_tree = treAstNewCatenation(mem.?, tmp_ast_l, tmp_ast_r) orelse {
            errcode = REG_ESPACE;
            break :error_block;
        };

        errcode = treComputeNfl(mem.?, stack.?, full_tree);
        if (errcode != REG_OK) break :error_block;

        const pos_count: usize = @intCast(parse_ctx.position);
        counts = @ptrCast(@alignCast(std.c.malloc(@sizeOf(c_int) * pos_count) orelse {
            errcode = REG_ESPACE;
            break :error_block;
        }));
        offs = @ptrCast(@alignCast(std.c.malloc(@sizeOf(c_int) * pos_count) orelse {
            errcode = REG_ESPACE;
            break :error_block;
        }));

        for (0..pos_count) |i| counts.?[i] = 0;
        _ = treAstToTnfa(full_tree, null, counts.?, null);

        var add: c_int = 0;
        for (0..pos_count) |i| {
            offs.?[i] = add;
            add += counts.?[i] + 1;
            counts.?[i] = 0;
        }

        const transitions: [*]TnfaTransition = @ptrCast(@alignCast(std.c.calloc(
            @intCast(add + 1),
            @sizeOf(TnfaTransition),
        ) orelse {
            errcode = REG_ESPACE;
            break :error_block;
        }));
        tnfa.?.transitions = transitions;
        tnfa.?.num_transitions = @intCast(add);

        errcode = treAstToTnfa(full_tree, transitions, counts.?, offs.?);
        if (errcode != REG_OK) break :error_block;

        tnfa.?.firstpos_chars = null;

        var p = full_tree.firstpos.?;
        var nfp: usize = 0;
        while (p[nfp].position >= 0) : (nfp += 1) {}

        const initial: [*]TnfaTransition = @ptrCast(@alignCast(std.c.calloc(
            nfp + 1,
            @sizeOf(TnfaTransition),
        ) orelse {
            errcode = REG_ESPACE;
            break :error_block;
        }));
        tnfa.?.initial = initial;

        p = full_tree.firstpos.?;
        var pi: usize = 0;
        while (p[pi].position >= 0) : (pi += 1) {
            initial[pi].state = @ptrCast(transitions + @as(usize, @intCast(offs.?[@intCast(p[pi].position)])));
            initial[pi].state_id = p[pi].position;
            initial[pi].tags = null;
            if (p[pi].tags) |pt| {
                var j: usize = 0;
                while (pt[j] >= 0) : (j += 1) {}
                const itags: [*]c_int = @ptrCast(@alignCast(std.c.malloc(@sizeOf(c_int) * (j + 1)) orelse {
                    errcode = REG_ESPACE;
                    break :error_block;
                }));
                _ = memcpy(@ptrCast(itags), @ptrCast(pt), @sizeOf(c_int) * (j + 1));
                initial[pi].tags = itags;
            }
            initial[pi].assertions = p[pi].assertions;
        }
        initial[pi].state = null;

        tnfa.?.num_transitions = @intCast(add);
        tnfa.?.final = @ptrCast(transitions + @as(usize, @intCast(offs.?[@intCast(full_tree.lastpos.?[0].position)])));
        tnfa.?.num_states = parse_ctx.position;
        tnfa.?.cflags = cflags;

        treMemDestroy(mem.?);
        mem = null;
        treStackDestroy(stack.?);
        stack = null;
        std.c.free(@ptrCast(counts.?));
        counts = null;
        std.c.free(@ptrCast(offs.?));
        offs = null;

        preg.__opaque = @ptrCast(tnfa.?);
        return REG_OK;
    }

    // Error cleanup
    if (mem) |m| treMemDestroy(m);
    if (stack) |s| treStackDestroy(s);
    if (counts) |c| std.c.free(@ptrCast(c));
    if (offs) |o| std.c.free(@ptrCast(o));
    preg.__opaque = @ptrCast(tnfa);
    regfreeImpl(preg);
    return errcode;
}

fn regfreeImpl(preg: *regex_t) callconv(.c) void {
    const tnfa_ptr = preg.__opaque orelse return;
    const tnfa: *Tnfa = @ptrCast(@alignCast(tnfa_ptr));

    if (tnfa.transitions) |trans| {
        var i: usize = 0;
        while (i < tnfa.num_transitions) : (i += 1) {
            if (trans[i].state != null) {
                if (trans[i].tags) |t| std.c.free(@ptrCast(t));
                if (trans[i].neg_classes) |nc| std.c.free(@ptrCast(nc));
            }
        }
        std.c.free(@ptrCast(trans));
    }

    if (tnfa.initial) |init| {
        var t = init;
        while (t[0].state != null) : (t += 1) {
            if (t[0].tags) |tg| std.c.free(@ptrCast(tg));
        }
        std.c.free(@ptrCast(init));
    }

    if (tnfa.submatch_data) |sd| {
        var i: usize = 0;
        while (i < tnfa.num_submatches) : (i += 1) {
            if (sd[i].parents) |p| std.c.free(@ptrCast(p));
        }
        std.c.free(@ptrCast(sd));
    }

    if (tnfa.tag_directions) |td| std.c.free(@ptrCast(td));
    if (tnfa.firstpos_chars) |fc| std.c.free(@ptrCast(fc));
    if (tnfa.minimal_tags) |mt| std.c.free(@ptrCast(mt));
    std.c.free(@ptrCast(tnfa));
    preg.__opaque = null;
}


// ============================================================
// Matchers
// ============================================================

// Parallel matcher
fn treTnfaRunParallel(
    tnfa: *Tnfa,
    string: [*]const u8,
    match_tags: ?[*]regoff_t,
    eflags: c_int,
    match_end_ofs: *regoff_t,
) reg_errcode_t {
    const TreReach = struct {
        state: ?*TnfaTransition,
        tags: [*]regoff_t,
    };
    const TreReachPos = struct {
        pos: regoff_t,
        tags: ?*[*]regoff_t,
    };

    var prev_c: wint_t = 0;
    var next_c: wint_t = 0;
    var str_byte: [*]const u8 = string;
    var pos: regoff_t = -1;
    var pos_add_next: regoff_t = 1;
    const reg_notbol = eflags & REG_NOTBOL;
    const reg_noteol = eflags & REG_NOTEOL;
    const reg_newline = tnfa.cflags & REG_NEWLINE;
    var ret: reg_errcode_t = REG_NOMATCH;

    const num_tags: c_int = if (match_tags != null) tnfa.num_tags else 0;

    if (tnfa.num_states == 0 or num_tags > @as(c_int, @intCast(std.math.maxInt(usize) / (8 * @sizeOf(regoff_t)) / @as(usize, @intCast(tnfa.num_states)))))
        if (tnfa.num_states > 0) return REG_ESPACE;

    const tbytes = @sizeOf(regoff_t) * @as(usize, @intCast(num_tags));
    const rbytes = @sizeOf(TreReach) * @as(usize, @intCast(tnfa.num_states + 1));
    const pbytes = @sizeOf(TreReachPos) * @as(usize, @intCast(tnfa.num_states));
    const xbytes = @sizeOf(regoff_t) * @as(usize, @intCast(num_tags));
    const total_bytes = (@sizeOf(c_long) - 1) * 4 +
        (rbytes + xbytes * @as(usize, @intCast(tnfa.num_states))) * 2 +
        tbytes + pbytes;

    const buf_raw = std.c.calloc(total_bytes, 1) orelse return REG_ESPACE;
    const buf: [*]u8 = @ptrCast(buf_raw);

    var tmp_tags: [*]regoff_t = @ptrCast(@alignCast(buf));
    var tmp_buf_off: usize = tbytes;
    tmp_buf_off += alignPad(tmp_buf_off, c_long);

    var reach_next: [*]TreReach = @ptrCast(@alignCast(buf + tmp_buf_off));
    tmp_buf_off += rbytes;
    tmp_buf_off += alignPad(tmp_buf_off, c_long);

    var reach: [*]TreReach = @ptrCast(@alignCast(buf + tmp_buf_off));
    tmp_buf_off += rbytes;
    tmp_buf_off += alignPad(tmp_buf_off, c_long);

    var reach_pos: [*]TreReachPos = @ptrCast(@alignCast(buf + tmp_buf_off));
    tmp_buf_off += pbytes;
    tmp_buf_off += alignPad(tmp_buf_off, c_long);

    for (0..@intCast(tnfa.num_states)) |i| {
        reach[i].tags = @ptrCast(@alignCast(buf + tmp_buf_off));
        tmp_buf_off += xbytes;
        reach_next[i].tags = @ptrCast(@alignCast(buf + tmp_buf_off));
        tmp_buf_off += xbytes;
    }

    for (0..@intCast(tnfa.num_states)) |i| reach_pos[i].pos = -1;

    // GET_NEXT_WCHAR inline
    {
        prev_c = next_c;
        pos += pos_add_next;
        const wlen = mbtowc(@ptrCast(&next_c), str_byte, MB_LEN_MAX);
        if (wlen <= 0) {
            if (wlen < 0) {
                match_end_ofs.* = -1;
                std.c.free(buf_raw);
                return REG_NOMATCH;
            }
            pos_add_next = 1;
        } else {
            pos_add_next = @intCast(wlen);
        }
        str_byte += @intCast(pos_add_next);
    }
    pos = 0;

    var match_eo: regoff_t = -1;
    var new_match: c_int = 0;
    var tmp_iptr: [*]regoff_t = undefined;

    var reach_next_i = reach_next;

    main_loop: while (true) {
        if (match_eo < 0) {
            var trans_i = tnfa.initial.?;
            while (trans_i[0].state != null) : (trans_i += 1) {
                if (reach_pos[@intCast(trans_i[0].state_id)].pos < pos) {
                    if (trans_i[0].assertions != 0 and checkAssertions(
                        trans_i[0].assertions, pos, prev_c, next_c, reg_notbol, reg_noteol, reg_newline,
                    )) {
                        continue;
                    }
                    reach_next_i[0].state = trans_i[0].state;
                    for (0..@intCast(num_tags)) |ti| reach_next_i[0].tags[ti] = -1;
                    if (trans_i[0].tags) |tag_i_arr| {
                        var tag_i: [*]c_int = tag_i_arr;
                        while (tag_i[0] >= 0) : (tag_i += 1) {
                            if (tag_i[0] < num_tags)
                                reach_next_i[0].tags[@intCast(tag_i[0])] = pos;
                        }
                    }
                    if (reach_next_i[0].state == tnfa.final) {
                        match_eo = pos;
                        new_match = 1;
                        for (0..@intCast(num_tags)) |ti|
                            match_tags.?[ti] = reach_next_i[0].tags[ti];
                    }
                    reach_pos[@intCast(trans_i[0].state_id)].pos = pos;
                    reach_pos[@intCast(trans_i[0].state_id)].tags = &reach_next_i[0].tags;
                    reach_next_i += 1;
                }
            }
            reach_next_i[0].state = null;
        } else {
            if (num_tags == 0 or reach_next_i == reach_next) break :main_loop;
        }

        if (next_c == 0) break :main_loop;

        // GET_NEXT_WCHAR
        {
            prev_c = next_c;
            pos += pos_add_next;
            const wlen = mbtowc(@ptrCast(&next_c), str_byte, MB_LEN_MAX);
            if (wlen <= 0) {
                if (wlen < 0) { ret = REG_NOMATCH; break :main_loop; }
                pos_add_next = 1;
            } else {
                pos_add_next = @intCast(wlen);
            }
            str_byte += @intCast(pos_add_next);
        }

        // Swap reach and reach_next
        {
            const tmp_reach = reach;
            reach = reach_next;
            reach_next = tmp_reach;
        }

        // Process minimals
        if (tnfa.num_minimals != 0 and new_match != 0) {
            new_match = 0;
            reach_next_i = reach_next;
            var reach_i = reach;
            while (reach_i[0].state != null) : (reach_i += 1) {
                var skip: c_int = 0;
                var mi: usize = 0;
                while (tnfa.minimal_tags.?[mi] >= 0) : (mi += 2) {
                    const end_t = tnfa.minimal_tags.?[mi];
                    const start_t = tnfa.minimal_tags.?[mi + 1];
                    if (end_t >= num_tags) { skip = 1; break; }
                    if (reach_i[0].tags[@intCast(start_t)] == match_tags.?[@intCast(start_t)] and
                        reach_i[0].tags[@intCast(end_t)] < match_tags.?[@intCast(end_t)])
                    {
                        skip = 1;
                        break;
                    }
                }
                if (skip == 0) {
                    reach_next_i[0].state = reach_i[0].state;
                    tmp_iptr = reach_next_i[0].tags;
                    reach_next_i[0].tags = reach_i[0].tags;
                    reach_i[0].tags = tmp_iptr;
                    reach_next_i += 1;
                }
            }
            reach_next_i[0].state = null;
            const tmp_reach = reach;
            reach = reach_next;
            reach_next = tmp_reach;
        }

        reach_next_i = reach_next;
        var reach_i2 = reach;
        while (reach_i2[0].state != null) : (reach_i2 += 1) {
            var trans_i2: [*]TnfaTransition = @ptrCast(reach_i2[0].state.?);
            while (trans_i2[0].state != null) : (trans_i2 += 1) {
                if (@as(wint_t, @intCast(trans_i2[0].code_min)) <= prev_c and
                    @as(wint_t, @intCast(trans_i2[0].code_max)) >= prev_c)
                {
                    if (trans_i2[0].assertions != 0 and (checkAssertions(
                        trans_i2[0].assertions, pos, prev_c, next_c, reg_notbol, reg_noteol, reg_newline,
                    ) or checkCharClasses(@ptrCast(trans_i2), tnfa, eflags, prev_c))) {
                        continue;
                    }

                    for (0..@intCast(num_tags)) |ti|
                        tmp_tags[ti] = reach_i2[0].tags[ti];
                    if (trans_i2[0].tags) |tag_arr| {
                        var tag_i: [*]c_int = tag_arr;
                        while (tag_i[0] >= 0) : (tag_i += 1) {
                            if (tag_i[0] < num_tags)
                                tmp_tags[@intCast(tag_i[0])] = pos;
                        }
                    }

                    if (reach_pos[@intCast(trans_i2[0].state_id)].pos < pos) {
                        reach_next_i[0].state = trans_i2[0].state;
                        tmp_iptr = reach_next_i[0].tags;
                        reach_next_i[0].tags = tmp_tags;
                        tmp_tags = tmp_iptr;
                        reach_pos[@intCast(trans_i2[0].state_id)].pos = pos;
                        reach_pos[@intCast(trans_i2[0].state_id)].tags = &reach_next_i[0].tags;

                        if (reach_next_i[0].state == tnfa.final and
                            (match_eo == -1 or (num_tags > 0 and
                                reach_next_i[0].tags[0] <= match_tags.?[0])))
                        {
                            match_eo = pos;
                            new_match = 1;
                            for (0..@intCast(num_tags)) |ti|
                                match_tags.?[ti] = reach_next_i[0].tags[ti];
                        }
                        reach_next_i += 1;
                    } else {
                        if (treTTagOrder(num_tags, tnfa.tag_directions.?, tmp_tags, reach_pos[@intCast(trans_i2[0].state_id)].tags.?.*)) {
                            tmp_iptr = reach_pos[@intCast(trans_i2[0].state_id)].tags.?.*;
                            reach_pos[@intCast(trans_i2[0].state_id)].tags.?.* = tmp_tags;
                            if (trans_i2[0].state == tnfa.final) {
                                match_eo = pos;
                                new_match = 1;
                                for (0..@intCast(num_tags)) |ti|
                                    match_tags.?[ti] = tmp_tags[ti];
                            }
                            tmp_tags = tmp_iptr;
                        }
                    }
                }
            }
        }
        reach_next_i[0].state = null;
    }

    match_end_ofs.* = match_eo;
    ret = if (match_eo >= 0) REG_OK else REG_NOMATCH;
    std.c.free(buf_raw);
    return ret;
}

fn treTTagOrder(num_tags: c_int, tag_directions: [*]c_int, t1: [*]regoff_t, t2: [*]regoff_t) bool {
    var i: usize = 0;
    while (i < @as(usize, @intCast(num_tags))) : (i += 1) {
        if (tag_directions[i] == TRE_TAG_MINIMIZE) {
            if (t1[i] < t2[i]) return true;
            if (t1[i] > t2[i]) return false;
        } else {
            if (t1[i] > t2[i]) return true;
            if (t1[i] < t2[i]) return false;
        }
    }
    return false;
}

fn checkAssertions(
    assertions: c_int,
    pos: regoff_t,
    prev_c: wint_t,
    next_c: wint_t,
    reg_notbol: c_int,
    reg_noteol: c_int,
    reg_newline: c_int,
) bool {
    if (assertions & ASSERT_AT_BOL != 0 and
        (pos > 0 or reg_notbol != 0) and
        (prev_c != '\n' or reg_newline == 0)) return true;
    if (assertions & ASSERT_AT_EOL != 0 and
        (next_c != 0 or reg_noteol != 0) and
        (next_c != '\n' or reg_newline == 0)) return true;
    if (assertions & ASSERT_AT_BOW != 0 and
        (isWordChar(prev_c) or !isWordChar(next_c))) return true;
    if (assertions & ASSERT_AT_EOW != 0 and
        (!isWordChar(prev_c) or isWordChar(next_c))) return true;
    if (assertions & ASSERT_AT_WB != 0 and
        (pos != 0 and next_c != 0 and
            isWordChar(prev_c) == isWordChar(next_c))) return true;
    if (assertions & ASSERT_AT_WB_NEG != 0 and
        (pos == 0 or next_c == 0 or
            isWordChar(prev_c) != isWordChar(next_c))) return true;
    return false;
}

fn treNegCharClassesMatch(classes: [*]wctype_t, wc: wint_t, icase: c_int) bool {
    var i: usize = 0;
    while (classes[i] != 0) : (i += 1) {
        if (icase == 0) {
            if (iswctype(wc, classes[i]) != 0) return true;
        } else {
            if (iswctype(towupper(wc), classes[i]) != 0 or
                iswctype(towlower(wc), classes[i]) != 0) return true;
        }
    }
    return false;
}

fn checkCharClasses(trans: *TnfaTransition, tnfa: *Tnfa, eflags: c_int, prev_c: wint_t) bool {
    _ = eflags;
    if (trans.assertions & ASSERT_CHAR_CLASS != 0) {
        if (tnfa.cflags & REG_ICASE == 0) {
            if (iswctype(prev_c, trans.u.char_class) == 0) return true;
        } else {
            if (iswctype(towlower(prev_c), trans.u.char_class) == 0 and
                iswctype(towupper(prev_c), trans.u.char_class) == 0) return true;
        }
    }
    if (trans.assertions & ASSERT_CHAR_CLASS_NEG != 0) {
        if (trans.neg_classes) |nc| {
            if (treNegCharClassesMatch(nc, prev_c, tnfa.cflags & REG_ICASE)) return true;
        }
    }
    return false;
}

// Backtrack matcher
const TreBtItem = struct {
    pos: regoff_t,
    str_byte: [*]const u8,
    state: ?*TnfaTransition,
    state_id: c_int,
    next_c: wint_t,
    tags: ?[*]regoff_t,
};

const TreBt = struct {
    item: TreBtItem,
    prev: ?*TreBt,
    next: ?*TreBt,
};

fn treTnfaRunBacktrack(
    tnfa: *Tnfa,
    string: [*]const u8,
    match_tags: ?[*]regoff_t,
    eflags: c_int,
    match_end_ofs: *regoff_t,
) reg_errcode_t {
    var prev_c: wint_t = 0;
    var next_c: wint_t = 0;
    var str_byte: [*]const u8 = string;
    var pos: regoff_t = 0;
    var pos_add_next: regoff_t = 1;
    const reg_notbol = eflags & REG_NOTBOL;
    const reg_noteol = eflags & REG_NOTEOL;
    const reg_newline = tnfa.cflags & REG_NEWLINE;

    var next_c_start: wint_t = 0;
    var str_byte_start: [*]const u8 = string;
    var pos_start: regoff_t = -1;

    var match_eo: regoff_t = -1;
    var tags: ?[*]regoff_t = null;
    var state: ?*TnfaTransition = null;
    var states_seen: ?[*]c_int = null;

    const mem = treMemNew() orelse return REG_ESPACE;
    var bt_stack: *TreBt = @ptrCast(@alignCast(treMemAlloc(mem, @sizeOf(TreBt)) orelse {
        treMemDestroy(mem);
        return REG_ESPACE;
    }));
    bt_stack.prev = null;
    bt_stack.next = null;

    if (tnfa.num_tags > 0) {
        tags = @ptrCast(@alignCast(std.c.malloc(@sizeOf(regoff_t) * @as(usize, @intCast(tnfa.num_tags))) orelse {
            treMemDestroy(mem);
            return REG_ESPACE;
        }));
    }

    var pmatch: ?[*]regmatch_t = null;
    if (tnfa.num_submatches > 0) {
        pmatch = @ptrCast(@alignCast(std.c.malloc(@sizeOf(regmatch_t) * tnfa.num_submatches) orelse {
            treMemDestroy(mem);
            if (tags) |t| std.c.free(@ptrCast(t));
            return REG_ESPACE;
        }));
    }

    if (tnfa.num_states > 0) {
        states_seen = @ptrCast(@alignCast(std.c.malloc(@sizeOf(c_int) * @as(usize, @intCast(tnfa.num_states))) orelse {
            treMemDestroy(mem);
            if (tags) |t| std.c.free(@ptrCast(t));
            if (pmatch) |p| std.c.free(@ptrCast(p));
            return REG_ESPACE;
        }));
    }

    var ret: c_int = REG_NOMATCH;

    restart: while (true) {
        for (0..@intCast(tnfa.num_tags)) |ti| {
            tags.?[ti] = -1;
            if (match_tags) |mt| mt[ti] = -1;
        }
        for (0..@intCast(tnfa.num_states)) |si| states_seen.?[si] = 0;

        state = null;
        pos = pos_start;

        // GET_NEXT_WCHAR
        {
            prev_c = next_c;
            pos += pos_add_next;
            const wlen = mbtowc(@ptrCast(&next_c), str_byte, MB_LEN_MAX);
            if (wlen <= 0) {
                if (wlen < 0) { ret = REG_NOMATCH; break :restart; }
                pos_add_next = 1;
            } else {
                pos_add_next = @intCast(wlen);
            }
            str_byte += @intCast(pos_add_next);
        }

        pos_start = pos;
        next_c_start = next_c;
        str_byte_start = str_byte;

        var next_tags: ?[*]c_int = null;
        var trans_i = tnfa.initial.?;
        while (trans_i[0].state != null) : (trans_i += 1) {
            if (trans_i[0].assertions != 0 and checkAssertions(
                trans_i[0].assertions, pos, prev_c, next_c,
                reg_notbol, reg_noteol, reg_newline,
            )) continue;
            if (state == null) {
                state = trans_i[0].state;
                next_tags = trans_i[0].tags;
            } else {
                if (bt_stack.next == null) {
                    const s: *TreBt = @ptrCast(@alignCast(treMemAlloc(mem, @sizeOf(TreBt)) orelse {
                        treMemDestroy(mem);
                        if (tags) |t| std.c.free(@ptrCast(t));
                        if (pmatch) |p| std.c.free(@ptrCast(p));
                        if (states_seen) |ss| std.c.free(@ptrCast(ss));
                        return REG_ESPACE;
                    }));
                    s.prev = bt_stack;
                    s.next = null;
                    s.item.tags = @ptrCast(@alignCast(treMemAlloc(mem, @sizeOf(regoff_t) * @as(usize, @intCast(tnfa.num_tags))) orelse {
                        treMemDestroy(mem);
                        if (tags) |t| std.c.free(@ptrCast(t));
                        if (pmatch) |p| std.c.free(@ptrCast(p));
                        if (states_seen) |ss| std.c.free(@ptrCast(ss));
                        return REG_ESPACE;
                    }));
                    bt_stack.next = s;
                    bt_stack = s;
                } else {
                    bt_stack = bt_stack.next.?;
                }
                bt_stack.item.pos = pos;
                bt_stack.item.str_byte = str_byte;
                bt_stack.item.state = trans_i[0].state;
                bt_stack.item.state_id = trans_i[0].state_id;
                bt_stack.item.next_c = next_c;
                for (0..@intCast(tnfa.num_tags)) |ti|
                    bt_stack.item.tags.?[ti] = tags.?[ti];
                if (trans_i[0].tags) |tt| {
                    var tmp_t: [*]c_int = tt;
                    while (tmp_t[0] >= 0) : (tmp_t += 1)
                        bt_stack.item.tags.?[@intCast(tmp_t[0])] = pos;
                }
            }
        }

        if (next_tags) |nt| {
            var t: [*]c_int = nt;
            while (t[0] >= 0) : (t += 1)
                tags.?[@intCast(t[0])] = pos;
        }

        if (state == null) {
            // goto backtrack
            if (bt_stack.prev) |_| {
                if (bt_stack.item.state.?.assertions & ASSERT_BACKREF != 0)
                    states_seen.?[@intCast(bt_stack.item.state_id)] = 0;
                pos = bt_stack.item.pos;
                str_byte = bt_stack.item.str_byte;
                state = bt_stack.item.state;
                next_c = bt_stack.item.next_c;
                for (0..@intCast(tnfa.num_tags)) |ti|
                    tags.?[ti] = bt_stack.item.tags.?[ti];
                bt_stack = bt_stack.prev.?;
            } else if (match_eo < 0) {
                if (next_c == 0) break :restart;
                next_c = next_c_start;
                str_byte = str_byte_start;
                continue :restart;
            } else {
                break :restart;
            }
        }

        inner: while (true) {
            var go_backtrack = false;

            if (state == tnfa.final) {
                if (match_eo < pos or (match_eo == pos and match_tags != null and
                    treTTagOrder(tnfa.num_tags, tnfa.tag_directions.?, tags.?, match_tags.?)))
                {
                    match_eo = pos;
                    if (match_tags) |mt| {
                        for (0..@as(usize, @intCast(tnfa.num_tags))) |ti| mt[ti] = tags.?[ti];
                    }
                }
                go_backtrack = true;
            }

            if (!go_backtrack) {
                if (state.?.assertions & ASSERT_BACKREF != 0) {
                    // Back reference
                    const bt_ref = state.?.u.backref;
                    treFillPmatch(
                        @intCast(bt_ref + 1), pmatch.?, tnfa.cflags & ~REG_NOSUB,
                        tnfa, tags.?, pos,
                    );
                    const so = pmatch.?[@intCast(bt_ref)].rm_so;
                    const eo = pmatch.?[@intCast(bt_ref)].rm_eo;
                    const bt_len = eo - so;

                    if (bt_len >= 0 and strncmp(
                        @ptrCast(string + @as(usize, @intCast(so))),
                        @ptrCast(str_byte - 1),
                        @intCast(bt_len),
                    ) == 0) {
                        const empty_br_match = (bt_len == 0);
                        if (empty_br_match and states_seen.?[@intCast(state.?.state_id)] != 0) {
                            go_backtrack = true;
                        } else {
                            states_seen.?[@intCast(state.?.state_id)] = if (empty_br_match) 1 else 0;
                            str_byte += @intCast(bt_len - 1);
                            pos += bt_len - 1;
                            // GET_NEXT_WCHAR
                            prev_c = next_c;
                            pos += pos_add_next;
                            const wlen = mbtowc(@ptrCast(&next_c), str_byte, MB_LEN_MAX);
                            if (wlen <= 0) {
                                if (wlen < 0) { ret = REG_NOMATCH; break :inner; }
                                pos_add_next = 1;
                            } else {
                                pos_add_next = @intCast(wlen);
                            }
                            str_byte += @intCast(pos_add_next);
                        }
                    } else {
                        go_backtrack = true;
                    }
                } else {
                    if (next_c == 0) {
                        go_backtrack = true;
                    } else {
                        // GET_NEXT_WCHAR
                        prev_c = next_c;
                        pos += pos_add_next;
                        const wlen = mbtowc(@ptrCast(&next_c), str_byte, MB_LEN_MAX);
                        if (wlen <= 0) {
                            if (wlen < 0) { ret = REG_NOMATCH; break :inner; }
                            pos_add_next = 1;
                        } else {
                            pos_add_next = @intCast(wlen);
                        }
                        str_byte += @intCast(pos_add_next);
                    }
                }
            }

            if (!go_backtrack) {
                var next_state: ?*TnfaTransition = null;
                var next_tags2: ?[*]c_int = null;
                var ti_arr: [*]TnfaTransition = @ptrCast(state.?);
                while (ti_arr[0].state != null) : (ti_arr += 1) {
                    if (@as(wint_t, @intCast(ti_arr[0].code_min)) <= prev_c and
                        @as(wint_t, @intCast(ti_arr[0].code_max)) >= prev_c)
                    {
                        if (ti_arr[0].assertions != 0 and (checkAssertions(
                            ti_arr[0].assertions, pos, prev_c, next_c,
                            reg_notbol, reg_noteol, reg_newline,
                        ) or checkCharClasses(@ptrCast(ti_arr), tnfa, eflags, prev_c))) continue;

                        if (next_state == null) {
                            next_state = ti_arr[0].state;
                            next_tags2 = ti_arr[0].tags;
                        } else {
                            if (bt_stack.next == null) {
                                const s: *TreBt = @ptrCast(@alignCast(treMemAlloc(mem, @sizeOf(TreBt)) orelse {
                                    ret = REG_ESPACE;
                                    break :inner;
                                }));
                                s.prev = bt_stack;
                                s.next = null;
                                s.item.tags = @ptrCast(@alignCast(treMemAlloc(mem, @sizeOf(regoff_t) * @as(usize, @intCast(tnfa.num_tags))) orelse {
                                    ret = REG_ESPACE;
                                    break :inner;
                                }));
                                bt_stack.next = s;
                                bt_stack = s;
                            } else {
                                bt_stack = bt_stack.next.?;
                            }
                            bt_stack.item.pos = pos;
                            bt_stack.item.str_byte = str_byte;
                            bt_stack.item.state = ti_arr[0].state;
                            bt_stack.item.state_id = ti_arr[0].state_id;
                            bt_stack.item.next_c = next_c;
                            for (0..@intCast(tnfa.num_tags)) |ti|
                                bt_stack.item.tags.?[ti] = tags.?[ti];
                            if (ti_arr[0].tags) |tt| {
                                var tmp_t: [*]c_int = tt;
                                while (tmp_t[0] >= 0) : (tmp_t += 1)
                                    bt_stack.item.tags.?[@intCast(tmp_t[0])] = pos;
                            }
                        }
                    }
                }

                if (next_state) |ns| {
                    state = ns;
                    if (next_tags2) |nt2| {
                        var t: [*]c_int = nt2;
                        while (t[0] >= 0) : (t += 1)
                            tags.?[@intCast(t[0])] = pos;
                    }
                    continue :inner;
                }
                go_backtrack = true;
            }

            // Backtrack
            if (go_backtrack) {
                if (bt_stack.prev) |_| {
                    if (bt_stack.item.state.?.assertions & ASSERT_BACKREF != 0)
                        states_seen.?[@intCast(bt_stack.item.state_id)] = 0;
                    pos = bt_stack.item.pos;
                    str_byte = bt_stack.item.str_byte;
                    state = bt_stack.item.state;
                    next_c = bt_stack.item.next_c;
                    for (0..@intCast(tnfa.num_tags)) |ti|
                        tags.?[ti] = bt_stack.item.tags.?[ti];
                    bt_stack = bt_stack.prev.?;
                    continue :inner;
                } else if (match_eo < 0) {
                    if (next_c == 0) break :inner;
                    next_c = next_c_start;
                    str_byte = str_byte_start;
                    continue :restart;
                } else {
                    break :inner;
                }
            }
        }

        break :restart;
    }

    ret = if (match_eo >= 0) REG_OK else REG_NOMATCH;
    match_end_ofs.* = match_eo;

    treMemDestroy(mem);
    if (tags) |t| std.c.free(@ptrCast(t));
    if (pmatch) |p| std.c.free(@ptrCast(p));
    if (states_seen) |ss| std.c.free(@ptrCast(ss));
    return ret;
}

// ============================================================
// tre_fill_pmatch and regexec
// ============================================================

fn treFillPmatch(
    nmatch: usize,
    pmatch: [*]regmatch_t,
    cflags: c_int,
    tnfa: *Tnfa,
    tags: ?[*]regoff_t,
    match_eo: regoff_t,
) void {
    var i: usize = 0;

    if (match_eo >= 0 and cflags & REG_NOSUB == 0) {
        const submatch_data = tnfa.submatch_data.?;
        while (i < tnfa.num_submatches and i < nmatch) : (i += 1) {
            if (submatch_data[i].so_tag == tnfa.end_tag) {
                pmatch[i].rm_so = match_eo;
            } else {
                pmatch[i].rm_so = tags.?[@intCast(submatch_data[i].so_tag)];
            }
            if (submatch_data[i].eo_tag == tnfa.end_tag) {
                pmatch[i].rm_eo = match_eo;
            } else {
                pmatch[i].rm_eo = tags.?[@intCast(submatch_data[i].eo_tag)];
            }
            if (pmatch[i].rm_so == -1 or pmatch[i].rm_eo == -1) {
                pmatch[i].rm_so = -1;
                pmatch[i].rm_eo = -1;
            }
        }
        i = 0;
        while (i < tnfa.num_submatches and i < nmatch) : (i += 1) {
            if (submatch_data[i].parents) |parents| {
                var j: usize = 0;
                while (parents[j] >= 0) : (j += 1) {
                    if (pmatch[i].rm_so < pmatch[@intCast(parents[j])].rm_so or
                        pmatch[i].rm_eo > pmatch[@intCast(parents[j])].rm_eo)
                    {
                        pmatch[i].rm_so = -1;
                        pmatch[i].rm_eo = -1;
                    }
                }
            }
        }
    }

    while (i < nmatch) : (i += 1) {
        pmatch[i].rm_so = -1;
        pmatch[i].rm_eo = -1;
    }
}

fn regexecImpl(
    preg: *const regex_t,
    string: [*:0]const u8,
    nmatch: usize,
    pmatch: ?[*]regmatch_t,
    eflags: c_int,
) callconv(.c) c_int {
    const tnfa: *Tnfa = @ptrCast(@alignCast(preg.__opaque.?));
    var status: reg_errcode_t = undefined;
    var tags: ?[*]regoff_t = null;
    var eo: regoff_t = undefined;

    var effective_nmatch = nmatch;
    if (tnfa.cflags & REG_NOSUB != 0) effective_nmatch = 0;

    if (tnfa.num_tags > 0 and effective_nmatch > 0) {
        tags = @ptrCast(@alignCast(std.c.malloc(@sizeOf(regoff_t) * @as(usize, @intCast(tnfa.num_tags))) orelse return REG_ESPACE));
    }

    if (tnfa.have_backrefs != 0) {
        status = treTnfaRunBacktrack(tnfa, @ptrCast(string), tags, eflags, &eo);
    } else {
        status = treTnfaRunParallel(tnfa, @ptrCast(string), tags, eflags, &eo);
    }

    if (status == REG_OK) {
        if (pmatch) |pm| {
            treFillPmatch(effective_nmatch, pm, tnfa.cflags, tnfa, tags, eo);
        }
    }
    if (tags) |t| std.c.free(@ptrCast(t));
    return status;
}


// ============================================================
// regerror
// ============================================================

const regErrorMessages =
    "No error\x00" ++
    "No match\x00" ++
    "Invalid regexp\x00" ++
    "Unknown collating element\x00" ++
    "Unknown character class name\x00" ++
    "Trailing backslash\x00" ++
    "Invalid back reference\x00" ++
    "Missing ']'\x00" ++
    "Missing ')'\x00" ++
    "Missing '}'\x00" ++
    "Invalid contents of {}\x00" ++
    "Invalid character range\x00" ++
    "Out of memory\x00" ++
    "Repetition not preceded by valid expression\x00" ++
    "\x00Unknown error";

fn regerrorImpl(
    e: c_int,
    preg: ?*const regex_t,
    buf: ?[*]u8,
    size: usize,
) callconv(.c) usize {
    _ = preg;
    const msgs: [*:0]const u8 = regErrorMessages;
    var s: [*]const u8 = msgs;
    var err = e;
    while (err != 0 and s[0] != 0) : (err -= 1) {
        s += strlen(@ptrCast(s)) + 1;
    }
    if (s[0] == 0) s += 1; // point to "Unknown error"
    const result = 1 + @as(usize, @intCast(snprintf(
        if (buf) |b| b else @as([*]u8, @ptrFromInt(1)),
        if (buf != null) size else 0,
        "%s",
        @as([*:0]const u8, @ptrCast(s)),
    )));
    return result;
}

// ============================================================
// fnmatch
// ============================================================

fn strNext(str: [*]const u8, n: usize, step: *usize) c_int {
    if (n == 0) {
        step.* = 0;
        return 0;
    }
    if (@as(u8, str[0]) >= 128) {
        var wc: wchar_t = 0;
        const k = mbtowc(&wc, str, n);
        if (k < 0) {
            step.* = 1;
            return -1;
        }
        step.* = @intCast(k);
        return wc;
    }
    step.* = 1;
    return str[0];
}

fn patNext(pat: [*]const u8, m: usize, step: *usize, flags: c_int) c_int {
    var esc: c_int = 0;
    if (m == 0 or pat[0] == 0) {
        step.* = 0;
        return FNM_END;
    }
    step.* = 1;
    if (pat[0] == '\\' and pat[1] != 0 and flags & FNM_NOESCAPE == 0) {
        step.* = 2;
        return patNextEscaped(pat + 1, m - 1, step, &esc);
    }
    if (pat[0] == '[') {
        var k: usize = 1;
        if (k < m) if (pat[k] == '^' or pat[k] == '!') { k += 1; };
        if (k < m) if (pat[k] == ']') { k += 1; };
        while (k < m and pat[k] != 0 and pat[k] != ']') : (k += 1) {
            if (k + 1 < m and pat[k + 1] != 0 and pat[k] == '[' and
                (pat[k + 1] == ':' or pat[k + 1] == '.' or pat[k + 1] == '='))
            {
                const z = pat[k + 1];
                k += 2;
                if (k < m and pat[k] != 0) k += 1;
                while (k < m and pat[k] != 0 and (pat[k - 1] != z or pat[k] != ']')) : (k += 1) {}
                if (k == m or pat[k] == 0) break;
            }
        }
        if (k == m or pat[k] == 0) {
            step.* = 1;
            return '[';
        }
        step.* = k + 1;
        return FNM_BRACKET;
    }
    if (pat[0] == '*') return FNM_STAR;
    if (pat[0] == '?') return FNM_QUESTION;

    return patNextEscaped(pat, m, step, &esc);
}

fn patNextEscaped(pat: [*]const u8, m: usize, step: *usize, esc: *c_int) c_int {
    if (@as(u8, pat[0]) >= 128) {
        var wc: wchar_t = 0;
        const k = mbtowc(&wc, pat, m);
        if (k < 0) {
            step.* = 0;
            return FNM_UNMATCHABLE;
        }
        step.* = @as(usize, @intCast(k)) + @as(usize, @intCast(esc.*));
        return wc;
    }
    step.* = 1 + @as(usize, @intCast(esc.*));
    return pat[0];
}

fn casefold(k: c_int) c_int {
    const c: wint_t = towupper(@intCast(k));
    return if (c == @as(wint_t, @intCast(k))) @intCast(towlower(@intCast(k))) else @intCast(c);
}

fn matchBracket(p_in: [*]const u8, k: c_int, kfold: c_int) c_int {
    var wc: wchar_t = 0;
    var inv: c_int = 0;
    var p = p_in + 1; // skip '['
    if (p[0] == '^' or p[0] == '!') {
        inv = 1;
        p += 1;
    }
    if (p[0] == ']') {
        if (k == ']') return 1 - inv;
        p += 1;
    } else if (p[0] == '-') {
        if (k == '-') return 1 - inv;
        p += 1;
    }
    wc = @intCast(@as(u8, (p - 1)[0]));
    while (p[0] != ']') : (p += 1) {
        if (p[0] == '-' and p[1] != ']') {
            var wc2: wchar_t = 0;
            const l = mbtowc(&wc2, p + 1, 4);
            if (l < 0) return 0;
            if (wc <= wc2) {
                const uk: c_uint = @bitCast(k);
                const ukfold: c_uint = @bitCast(kfold);
                const uwc: c_uint = @bitCast(wc);
                const uwc2: c_uint = @bitCast(wc2);
                if (uk -% uwc <= uwc2 -% uwc or ukfold -% uwc <= uwc2 -% uwc)
                    return 1 - inv;
            }
            p += @intCast(l - 1);
            continue;
        }
        if (p[0] == '[' and (p[1] == ':' or p[1] == '.' or p[1] == '=')) {
            const p0 = p + 2;
            const z = p[1];
            p += 3;
            while ((p - 1)[0] != z or p[0] != ']') : (p += 1) {}
            if (z == ':') {
                const cls_len = @intFromPtr(p) - 1 - @intFromPtr(p0);
                if (cls_len < 16) {
                    var buf: [16]u8 = undefined;
                    const l = cls_len;
                    @memcpy(buf[0..l], p0[0..l]);
                    buf[l] = 0;
                    if (iswctype(@intCast(k), wctype(@ptrCast(&buf))) != 0 or
                        iswctype(@intCast(kfold), wctype(@ptrCast(&buf))) != 0)
                        return 1 - inv;
                }
            }
            continue;
        }
        if (@as(u8, p[0]) < 128) {
            wc = @intCast(@as(u8, p[0]));
        } else {
            const l = mbtowc(&wc, p, 4);
            if (l < 0) return 0;
            p += @intCast(l - 1);
        }
        if (wc == k or wc == kfold) return 1 - inv;
    }
    return inv;
}

fn fnmatchInternal(
    pat_in: [*]const u8,
    m_in: usize,
    str_in: [*]const u8,
    n_in: usize,
    flags: c_int,
) c_int {
    var pat = pat_in;
    var m = m_in;
    var str = str_in;
    var n = n_in;

    if (flags & FNM_PERIOD != 0) {
        if (str[0] == '.' and pat[0] != '.') return FNM_NOMATCH;
    }

    // Process head: consume until first STAR
    var pinc: usize = 0;
    var sinc: usize = 0;
    var c: c_int = 0;
    var k: c_int = 0;

    while (true) {
        c = patNext(pat, m, &pinc, flags);
        switch (c) {
            FNM_UNMATCHABLE => return FNM_NOMATCH,
            FNM_STAR => {
                pat += 1;
                m -= 1;
                break;
            },
            else => {
                k = strNext(str, n, &sinc);
                if (k <= 0) return if (c == FNM_END) 0 else FNM_NOMATCH;
                str += sinc;
                n -= sinc;
                const kfold: c_int = if (flags & FNM_CASEFOLD != 0) casefold(k) else k;
                if (c == FNM_BRACKET) {
                    if (matchBracket(pat, k, kfold) == 0) return FNM_NOMATCH;
                } else if (c != FNM_QUESTION and k != c and kfold != c) {
                    return FNM_NOMATCH;
                }
                pat += pinc;
                m -= pinc;
                continue;
            },
        }
    }

    // Compute real pat length
    m = strnlen(pat, m);
    const endpat = pat + m;

    // Find last * in pat and count chars needed after it
    var p = pat;
    var ptail = pat;
    var tailcnt: usize = 0;
    while (@intFromPtr(p) < @intFromPtr(endpat)) {
        const pp = p;
        c = patNext(pp, @intFromPtr(endpat) - @intFromPtr(pp), &pinc, flags);
        p += pinc;
        switch (c) {
            FNM_UNMATCHABLE => return FNM_NOMATCH,
            FNM_STAR => {
                tailcnt = 0;
                ptail = pp + 1;
            },
            else => tailcnt += 1,
        }
    }

    // Compute real str length
    n = strnlen(str, n);
    const endstr = str + n;
    if (n < tailcnt) return FNM_NOMATCH;

    // Find final tailcnt chars of str
    var s = endstr;
    var tc = tailcnt;
    while (@intFromPtr(s) > @intFromPtr(str) and tc > 0) : (tc -= 1) {
        if ((s - 1)[0] < 128) {
            s -= 1;
        } else {
            s -= 1;
            while (@intFromPtr(s) > @intFromPtr(str) and @as(u8, s[0]) -% 0x80 < 0x40) {
                s -= 1;
            }
        }
    }
    if (tc != 0) return FNM_NOMATCH;
    const stail = s;

    // Check tail match
    p = ptail;
    s = stail;
    while (true) {
        c = patNext(p, @intFromPtr(endpat) - @intFromPtr(p), &pinc, flags);
        p += pinc;
        k = strNext(s, @intFromPtr(endstr) - @intFromPtr(s), &sinc);
        if (k <= 0) {
            if (c != FNM_END) return FNM_NOMATCH;
            break;
        }
        s += sinc;
        const kfold: c_int = if (flags & FNM_CASEFOLD != 0) casefold(k) else k;
        if (c == FNM_BRACKET) {
            if (matchBracket(p - pinc, k, kfold) == 0) return FNM_NOMATCH;
        } else if (c != FNM_QUESTION and k != c and kfold != c) {
            return FNM_NOMATCH;
        }
    }

    const endstr2 = stail;
    const endpat2 = ptail;

    // Match pattern components
    var str2 = str;
    var pat2 = pat;
    while (@intFromPtr(pat2) < @intFromPtr(endpat2)) {
        p = pat2;
        s = str2;
        var matched = false;
        comp_loop: while (true) {
            c = patNext(p, @intFromPtr(endpat2) - @intFromPtr(p), &pinc, flags);
            p += pinc;
            if (c == FNM_STAR) {
                pat2 = p;
                str2 = s;
                matched = true;
                break :comp_loop;
            }
            k = strNext(s, @intFromPtr(endstr2) - @intFromPtr(s), &sinc);
            if (k == 0) {
                // failed
                break :comp_loop;
            }
            const kfold2: c_int = if (flags & FNM_CASEFOLD != 0) casefold(k) else k;
            if (c == FNM_BRACKET) {
                if (matchBracket(p - pinc, k, kfold2) == 0) break :comp_loop;
            } else if (c != FNM_QUESTION and k != c and kfold2 != c) {
                break :comp_loop;
            }
            s += sinc;
        }
        if (matched) continue;
        // advance str2
        k = strNext(str2, @intFromPtr(endstr2) - @intFromPtr(str2), &sinc);
        if (k > 0) {
            str2 += sinc;
        } else {
            str2 += 1;
            while (strNext(str2, @intFromPtr(endstr2) - @intFromPtr(str2), &sinc) < 0) str2 += 1;
        }
    }

    return 0;
}

fn fnmatchImpl(pat: [*:0]const u8, str: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    const SIZE_MAX = std.math.maxInt(usize);

    if (flags & FNM_PATHNAME != 0) {
        var s: [*]const u8 = @ptrCast(str);
        var p: [*]const u8 = @ptrCast(pat);
        while (true) {
            var ss = s;
            while (ss[0] != 0 and ss[0] != '/') : (ss += 1) {}
            var inc: usize = 0;
            var pp = p;
            var cv: c_int = patNext(pp, SIZE_MAX, &inc, flags);
            while (cv != FNM_END and cv != '/') {
                pp += inc;
                cv = patNext(pp, SIZE_MAX, &inc, flags);
            }
            if (cv != @as(c_int, ss[0]) and (ss[0] != 0 or flags & FNM_LEADING_DIR == 0))
                return FNM_NOMATCH;
            if (fnmatchInternal(p, @intFromPtr(pp) - @intFromPtr(p), s, @intFromPtr(ss) - @intFromPtr(s), flags) != 0)
                return FNM_NOMATCH;
            if (cv == 0) return 0;
            s = ss + 1;
            p = pp + inc;
        }
    } else if (flags & FNM_LEADING_DIR != 0) {
        var s: [*]const u8 = @ptrCast(str);
        while (s[0] != 0) : (s += 1) {
            if (s[0] != '/') continue;
            if (fnmatchInternal(@ptrCast(pat), SIZE_MAX, @ptrCast(str), @intFromPtr(s) - @intFromPtr(@as([*]const u8, @ptrCast(str))), flags) == 0)
                return 0;
        }
    }
    return fnmatchInternal(@ptrCast(pat), SIZE_MAX, @ptrCast(str), SIZE_MAX, flags);
}


// ============================================================
// glob
// ============================================================

const GlobMatch = extern struct {
    next: ?*GlobMatch,
    // flexible array `char name[]` follows immediately
};

fn globMatchName(m: *GlobMatch) [*]u8 {
    return @as([*]u8, @ptrCast(m)) + @sizeOf(GlobMatch);
}

fn globAppend(tail: **GlobMatch, name: [*]const u8, len: usize, mark: c_int) c_int {
    const new: *GlobMatch = @ptrCast(@alignCast(std.c.malloc(@sizeOf(GlobMatch) + len + 2) orelse return -1));
    tail.*.next = new;
    new.next = null;
    const nfield = globMatchName(new);
    @memcpy(nfield[0 .. len + 1], name[0 .. len + 1]);
    if (mark != 0 and len > 0 and name[len - 1] != '/') {
        nfield[len] = '/';
        nfield[len + 1] = 0;
    }
    tail.* = new;
    return 0;
}

fn doGlob(
    buf: [*]u8,
    pos_in: usize,
    type_in: u8,
    pat_in: [*]u8,
    flags: c_int,
    errfunc: *const fn ([*:0]const u8, c_int) callconv(.c) c_int,
    tail_ptr: **GlobMatch,
) c_int {
    var pos = pos_in;
    var @"type" = type_in;
    var pat = pat_in;

    if (@"type" == 0 and flags & GLOB_MARK == 0) @"type" = DT_REG;
    if (pat[0] != 0 and @"type" != DT_DIR) @"type" = 0;
    while (pos + 1 < PATH_MAX and pat[0] == '/') {
        buf[pos] = '/';
        pos += 1;
        pat += 1;
    }

    // Consume literal prefix
    var i: usize = 0;
    var j: usize = 0;
    var in_bracket: c_int = 0;
    var overflow: c_int = 0;
    prefix_loop: while (pat[i] != '*' and pat[i] != '?' and (in_bracket == 0 or pat[i] != ']')) : (i += 1) {
        if (pat[i] == 0) {
            if (overflow != 0) return 0;
            pat += i;
            pos += j;
            i = 0;
            j = 0;
            break :prefix_loop;
        } else if (pat[i] == '[') {
            in_bracket = 1;
        } else if (pat[i] == '\\' and flags & GLOB_NOESCAPE == 0) {
            if (in_bracket != 0 and pat[i + 1] == ']') break :prefix_loop;
            if (pat[i + 1] == 0) return 0;
            i += 1;
        }
        if (pat[i] == '/') {
            if (overflow != 0) return 0;
            in_bracket = 0;
            pat += i + 1;
            i = @bitCast(@as(isize, -1));
            pos += j + 1;
            j = @bitCast(@as(isize, -1));
        }
        if (pos + (j + 1) < PATH_MAX) {
            buf[pos + j] = pat[i];
            j += 1;
        } else if (in_bracket != 0) {
            overflow = 1;
        } else {
            return 0;
        }
        @"type" = 0;
    }
    buf[pos] = 0;

    if (pat[0] == 0) {
        var st: Stat = undefined;
        if (flags & GLOB_MARK != 0 and (@"type" == 0 or @"type" == DT_LNK) and
            stat(@ptrCast(buf), &st) == 0)
        {
            if (sIsDir(st.st_mode)) @"type" = DT_DIR else @"type" = DT_REG;
        }
        if (@"type" == 0) {
            if (lstat(@ptrCast(buf), &st) != 0) {
                const en = std.c._errno().*;
                if (en != @intFromEnum(std.c.E.NOENT)) {
                    if (errfunc(@ptrCast(buf), en) != 0 or flags & GLOB_ERR != 0)
                        return GLOB_ABORTED;
                }
                return 0;
            }
        }
        if (globAppend(tail_ptr, buf, pos, if (flags & GLOB_MARK != 0 and @"type" == DT_DIR) 1 else 0) != 0)
            return GLOB_NOSPACE;
        return 0;
    }

    // Find next '/'
    var p2: ?[*]u8 = null;
    var saved_sep: u8 = '/';
    {
        var tmp = pat;
        while (tmp[0] != 0 and tmp[0] != '/') : (tmp += 1) {}
        if (tmp[0] == '/') {
            p2 = tmp;
            if (flags & GLOB_NOESCAPE == 0) {
                var pp = tmp;
                while (@intFromPtr(pp) > @intFromPtr(pat) and (pp - 1)[0] == '\\') : (pp -= 1) {}
                const backslashes = @intFromPtr(tmp) - @intFromPtr(pp);
                if (backslashes % 2 == 1) {
                    p2 = tmp - 1;
                    saved_sep = '\\';
                }
            }
        }
    }

    const dir_path: [*:0]const u8 = if (pos > 0) @ptrCast(buf) else ".";
    const dir = opendir(dir_path) orelse {
        const en = std.c._errno().*;
        if (errfunc(@ptrCast(buf), en) != 0 or flags & GLOB_ERR != 0)
            return GLOB_ABORTED;
        return 0;
    };

    const old_errno = std.c._errno().*;
    while (true) {
        std.c._errno().* = 0;
        const de = readdir(dir) orelse break;
        if (p2 != null and de.d_type != 0 and de.d_type != DT_DIR and de.d_type != DT_LNK)
            continue;
        const l = strlen(@ptrCast(&de.d_name));
        if (l >= PATH_MAX - pos) continue;

        if (p2) |p2v| p2v[0] = 0;

        const fnm_flags: c_int =
            (if (flags & GLOB_NOESCAPE != 0) FNM_NOESCAPE else 0) |
            (if (flags & GLOB_PERIOD == 0) FNM_PERIOD else 0);

        if (fnmatchImpl(@ptrCast(&de.d_name), @ptrCast(pat), fnm_flags) != 0) {
            if (p2) |p2v| p2v[0] = saved_sep;
            continue;
        }

        if (p2 != null and flags & GLOB_PERIOD != 0 and de.d_name[0] == '.' and
            (de.d_name[1] == 0 or (de.d_name[1] == '.' and de.d_name[2] == 0)) and
            fnmatchImpl(@ptrCast(&de.d_name), @ptrCast(pat), fnm_flags | FNM_PERIOD) != 0)
        {
            if (p2) |p2v| p2v[0] = saved_sep;
            continue;
        }

        @memcpy(buf[pos .. pos + l + 1], de.d_name[0 .. l + 1]);
        if (p2) |p2v| p2v[0] = saved_sep;

        const next_pat: [*]u8 = if (p2) |p2v| p2v else @as([*]u8, @ptrCast(@constCast("")));
        const r = doGlob(buf, pos + l, de.d_type, next_pat, flags, errfunc, tail_ptr);
        if (r != 0) {
            _ = closedir(dir);
            return r;
        }
    }
    const readerr = std.c._errno().*;
    if (p2) |p2v| p2v[0] = saved_sep;
    _ = closedir(dir);
    if (readerr != 0) {
        if (errfunc(@ptrCast(buf), readerr) != 0 or flags & GLOB_ERR != 0)
            return GLOB_ABORTED;
    }
    std.c._errno().* = old_errno;
    return 0;
}

fn ignoreErr(path: [*:0]const u8, err: c_int) callconv(.c) c_int {
    _ = path;
    _ = err;
    return 0;
}

fn freeGlobList(head: *GlobMatch) void {
    var match = head.next;
    while (match) |m| {
        const next = m.next;
        std.c.free(m);
        match = next;
    }
}

fn globSort(a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int {
    const pa = @as(*const ?[*:0]const u8, @ptrCast(@alignCast(a)));
    const pb = @as(*const ?[*:0]const u8, @ptrCast(@alignCast(b)));
    return strcmp(pa.*.?, pb.*.?);
}

fn expandTilde(pat_ptr: *[*]u8, buf: [*]u8, pos_out: *usize) c_int {
    const p: [*]u8 = pat_ptr.* + 1;
    var i: usize = 0;
    const name_end = __strchrnul(p, '/');
    const delim = name_end[0];
    if (delim != 0) name_end[0] = 0;
    const name_end_next: [*]u8 = if (delim != 0) name_end + 1 else name_end;
    pat_ptr.* = name_end_next;

    var home: ?[*:0]u8 = if (p[0] == 0) getenv("HOME") else null;
    if (home == null) {
        var pw: Passwd = undefined;
        var res: ?*Passwd = null;
        const rc: c_int = if (p[0] != 0)
            getpwnam_r(@ptrCast(p), &pw, buf, PATH_MAX, &res)
        else
            getpwuid_r(getuid(), &pw, buf, PATH_MAX, &res);
        switch (rc) {
            @intFromEnum(std.c.E.NOMEM) => return GLOB_NOSPACE,
            0 => {
                if (res == null) return GLOB_NOMATCH;
            },
            else => return GLOB_NOMATCH,
        }
        home = pw.pw_dir;
    }
    if (home) |h| {
        var hi: usize = 0;
        while (i < PATH_MAX - 2 and h[hi] != 0) : ({ i += 1; hi += 1; }) {
            buf[i] = h[hi];
        }
        if (h[hi] != 0) return GLOB_NOMATCH;
    }
    buf[i] = delim;
    if (delim != 0) {
        i += 1;
        buf[i] = 0;
    }
    pos_out.* = i;
    return 0;
}

fn globImpl(
    pat_in: [*:0]const u8,
    flags: c_int,
    errfunc_in: ?*const fn ([*:0]const u8, c_int) callconv(.c) c_int,
    g: *glob_t,
) callconv(.c) c_int {
    var head = GlobMatch{ .next = null };
    var tail: *GlobMatch = &head;
    const offs: usize = if (flags & GLOB_DOOFFS != 0) g.gl_offs else 0;
    var @"error": c_int = 0;
    var buf: [PATH_MAX]u8 = undefined;
    const errfunc = errfunc_in orelse &ignoreErr;

    if (flags & GLOB_APPEND == 0) {
        g.gl_offs = offs;
        g.gl_pathc = 0;
        g.gl_pathv = null;
    }

    if (pat_in[0] != 0) {
        const p = strdup(pat_in) orelse return GLOB_NOSPACE;
        buf[0] = 0;
        var pos: usize = 0;
        var s: [*]u8 = p;
        if (flags & (GLOB_TILDE | GLOB_TILDE_CHECK) != 0 and p[0] == '~') {
            @"error" = expandTilde(&s, &buf, &pos);
        }
        if (@"error" == 0) {
            @"error" = doGlob(&buf, pos, 0, s, flags, errfunc, &tail);
        }
        std.c.free(p);
    }

    if (@"error" == GLOB_NOSPACE) {
        freeGlobList(&head);
        return @"error";
    }

    var cnt: usize = 0;
    var t = head.next;
    while (t) |tm| : (t = tm.next) cnt += 1;

    if (cnt == 0) {
        if (flags & GLOB_NOCHECK != 0) {
            tail = &head;
            if (globAppend(&tail, @ptrCast(pat_in), strlen(pat_in), 0) != 0)
                return GLOB_NOSPACE;
            cnt += 1;
        } else if (@"error" == 0) {
            return GLOB_NOMATCH;
        }
    }

    if (flags & GLOB_APPEND != 0) {
        const pathv: ?[*]?[*:0]u8 = @ptrCast(@alignCast(std.c.realloc(
            @ptrCast(g.gl_pathv),
            (offs + g.gl_pathc + cnt + 1) * @sizeOf(?[*:0]u8),
        )));
        if (pathv == null) {
            freeGlobList(&head);
            return GLOB_NOSPACE;
        }
        g.gl_pathv = pathv;
        // offs += g.gl_pathc (for append)
        const base_offs = offs + g.gl_pathc;
        var i: usize = 0;
        var tm2 = head.next;
        while (tm2) |m| : ({ tm2 = m.next; i += 1; }) {
            pathv.?[base_offs + i] = @ptrCast(globMatchName(m));
        }
        pathv.?[base_offs + i] = null;
        g.gl_pathc += cnt;
        if (flags & GLOB_NOSORT == 0)
            qsort(@ptrCast(&pathv.?[base_offs]), cnt, @sizeOf(?[*:0]u8), &globSort);
    } else {
        const pathv: ?[*]?[*:0]u8 = @ptrCast(@alignCast(std.c.malloc(
            (offs + cnt + 1) * @sizeOf(?[*:0]u8),
        )));
        if (pathv == null) {
            freeGlobList(&head);
            return GLOB_NOSPACE;
        }
        g.gl_pathv = pathv;
        var i: usize = 0;
        while (i < offs) : (i += 1) pathv.?[i] = null;
        var tm3 = head.next;
        var j: usize = 0;
        while (tm3) |m| : ({ tm3 = m.next; j += 1; }) {
            pathv.?[offs + j] = @ptrCast(globMatchName(m));
        }
        pathv.?[offs + j] = null;
        g.gl_pathc += cnt;
        if (flags & GLOB_NOSORT == 0)
            qsort(@ptrCast(&pathv.?[offs]), cnt, @sizeOf(?[*:0]u8), &globSort);
    }

    return @"error";
}

fn globfreeImpl(g: *glob_t) callconv(.c) void {
    if (g.gl_pathv) |pathv| {
        var i: usize = 0;
        while (i < g.gl_pathc) : (i += 1) {
            if (pathv[g.gl_offs + i]) |p| {
                const raw: [*]u8 = @ptrCast(p);
                std.c.free(@ptrCast(raw - @sizeOf(GlobMatch)));
            }
        }
        std.c.free(@ptrCast(pathv));
    }
    g.gl_pathc = 0;
    g.gl_pathv = null;
}

// ============================================================
// Symbol exports
// ============================================================

comptime {
    if (builtin.link_libc) {
        symbol(&regcompImpl, "regcomp");
        symbol(&regexecImpl, "regexec");
        symbol(&regfreeImpl, "regfree");
        symbol(&regerrorImpl, "regerror");
        symbol(&fnmatchImpl, "fnmatch");
        symbol(&globImpl, "glob");
        symbol(&globfreeImpl, "globfree");
    }
}
