const std = @import("std");
const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&insque, "insque");
        symbol(&remque, "remque");
        symbol(&tsearchImpl, "tsearch");
        symbol(&tfindImpl, "tfind");
        symbol(&tdeleteImpl, "tdelete");
        symbol(&tdestroyImpl, "tdestroy");
        symbol(&twalkImpl, "twalk");
        symbol(&lsearchImpl, "lsearch");
        symbol(&lfindImpl, "lfind");
        symbol(&hcreateImpl, "hcreate");
        symbol(&hdestroyImpl, "hdestroy");
        symbol(&hsearchImpl, "hsearch");
        symbol(&hcreate_rImpl, "hcreate_r");
        symbol(&hdestroy_rImpl, "hdestroy_r");
        symbol(&hsearch_rImpl, "hsearch_r");
    }
}

// ── Queue (insque / remque) ──────────────────────────────────────────

const Node = extern struct {
    next: ?*Node,
    prev: ?*Node,
};

fn insque(element: *anyopaque, pred: ?*anyopaque) callconv(.c) void {
    const e: *Node = @ptrCast(@alignCast(element));

    if (pred) |p_ptr| {
        const p: *Node = @ptrCast(@alignCast(p_ptr));
        e.next = p.next;
        e.prev = p;
        p.next = e;

        if (e.next) |next| {
            next.prev = e;
        }
    } else {
        e.next = null;
        e.prev = null;
    }
}

fn remque(element: *anyopaque) callconv(.c) void {
    const e: *Node = @ptrCast(@alignCast(element));

    if (e.next) |next| next.prev = e.prev;
    if (e.prev) |prev| prev.next = e.next;
}

// ── AVL Tree (tsearch / tfind / tdelete / tdestroy / twalk) ──────────

const MAXH = @sizeOf(*anyopaque) * 8 * 3 / 2;

const TreeNode = extern struct {
    key: ?*const anyopaque,
    a: [2]?*anyopaque,
    h: c_int,
};

const ComparFn = *const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int;

fn treeNodeFromPtr(p: ?*anyopaque) ?*TreeNode {
    if (p) |ptr| {
        return @ptrCast(@alignCast(ptr));
    }
    return null;
}

fn height(p: ?*anyopaque) c_int {
    if (treeNodeFromPtr(p)) |n| return n.h;
    return 0;
}

fn rot(p: *?*anyopaque, x: *TreeNode, dir: u1) c_int {
    const hx = x.h;
    const y: *TreeNode = @ptrCast(@alignCast(x.a[dir].?));
    const not_dir: u1 = dir ^ 1;
    const z_ptr = y.a[not_dir];
    const hz = height(z_ptr);
    if (hz > height(y.a[dir])) {
        const z: *TreeNode = @ptrCast(@alignCast(z_ptr.?));
        x.a[dir] = z.a[not_dir];
        y.a[not_dir] = z.a[dir];
        z.a[not_dir] = @ptrCast(x);
        z.a[dir] = @ptrCast(y);
        x.h = hz;
        y.h = hz;
        z.h = hz + 1;
        p.* = @ptrCast(z);
        return z.h - hx;
    } else {
        x.a[dir] = z_ptr;
        y.a[not_dir] = @ptrCast(x);
        x.h = hz + 1;
        y.h = hz + 2;
        p.* = @ptrCast(y);
        return y.h - hx;
    }
}

fn balance(p: *?*anyopaque) c_int {
    const n: *TreeNode = @ptrCast(@alignCast(p.*.?));
    const h0 = height(n.a[0]);
    const h1 = height(n.a[1]);
    if (@as(c_uint, @bitCast(h0 - h1 + 1)) < 3) {
        const old = n.h;
        n.h = if (h0 < h1) h1 + 1 else h0 + 1;
        return n.h - old;
    }
    return rot(p, n, @intCast(@intFromBool(h0 < h1)));
}

fn tsearchImpl(key: ?*const anyopaque, rootp: ?*?*anyopaque, cmp: ComparFn) callconv(.c) ?*anyopaque {
    if (rootp == null) return null;
    var a: [MAXH]*?*anyopaque = undefined;
    var i: usize = 0;
    a[i] = rootp.?;
    i += 1;

    var np: *?*anyopaque = rootp.?;
    while (treeNodeFromPtr(np.*)) |n| {
        const c = cmp(key, n.key);
        const dir: usize = @intCast(@intFromBool(c > 0));
        a[i] = @ptrCast(&n.a[dir]);
        i += 1;
        np = @ptrCast(&n.a[dir]);
        if (c == 0) return @ptrCast(n);
    } else {
        // Not found — allocate a new node.
        const new_node: ?*TreeNode = @ptrCast(@alignCast(std.c.malloc(@sizeOf(TreeNode))));
        if (new_node) |nn| {
            nn.key = key;
            nn.a = .{ null, null };
            nn.h = 1;
            np.* = @ptrCast(nn);
            // Rebalance ancestors.
            while (i > 0) {
                i -= 1;
                if (balance(a[i]) == 0) break;
            }
            return @ptrCast(nn);
        }
        return null;
    }
}

fn tfindImpl(key: ?*const anyopaque, rootp: ?*const ?*anyopaque, cmp: ComparFn) callconv(.c) ?*anyopaque {
    if (rootp == null) return null;
    var n = treeNodeFromPtr(@constCast(rootp.?.*));
    while (n) |node| {
        const c = cmp(key, node.key);
        if (c == 0) return @ptrCast(node);
        const dir: usize = @intCast(@intFromBool(c > 0));
        n = treeNodeFromPtr(node.a[dir]);
    }
    return null;
}

fn tdeleteImpl(key: ?*const anyopaque, rootp: ?*?*anyopaque, cmp: ComparFn) callconv(.c) ?*anyopaque {
    if (rootp == null) return null;
    var a: [MAXH + 1]*?*anyopaque = undefined;
    var i: usize = 0;
    // Store rootp twice at start, matching musl.
    a[i] = rootp.?;
    i += 1;
    a[i] = rootp.?;
    i += 1;

    var n = treeNodeFromPtr(rootp.?.*);
    while (true) {
        if (n == null) return null;
        const c = cmp(key, n.?.key);
        if (c == 0) break;
        const dir: usize = @intCast(@intFromBool(c > 0));
        a[i] = @ptrCast(&n.?.a[dir]);
        i += 1;
        n = treeNodeFromPtr(n.?.a[dir]);
    }
    const parent: *TreeNode = @ptrCast(@alignCast(a[i - 2].*));
    var node = n.?;
    var child: ?*anyopaque = undefined;
    if (node.a[0] != null) {
        const deleted = node;
        a[i] = @ptrCast(&node.a[0]);
        i += 1;
        var cur = treeNodeFromPtr(node.a[0]).?;
        while (cur.a[1] != null) {
            a[i] = @ptrCast(&cur.a[1]);
            i += 1;
            cur = treeNodeFromPtr(cur.a[1]).?;
        }
        deleted.key = cur.key;
        child = cur.a[0];
        node = cur;
    } else {
        child = node.a[1];
    }
    std.c.free(@ptrCast(node));
    i -= 1;
    a[i].* = child;
    while (i > 0) {
        i -= 1;
        if (balance(a[i]) == 0) break;
        if (i == 0) break;
    }
    return @ptrCast(parent);
}

fn tdestroyImpl(root: ?*anyopaque, freekey: ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) void {
    tdestroy_recurse(root, freekey);
}

fn tdestroy_recurse(p: ?*anyopaque, freekey: ?*const fn (?*anyopaque) callconv(.c) void) void {
    const node = treeNodeFromPtr(p) orelse return;
    tdestroy_recurse(node.a[0], freekey);
    tdestroy_recurse(node.a[1], freekey);
    if (freekey) |fk| {
        if (node.key) |k| {
            fk(@constCast(k));
        }
    }
    std.c.free(@ptrCast(node));
}

const VISIT = enum(c_int) { preorder = 0, postorder = 1, endorder = 2, leaf = 3 };

fn twalkImpl(root: ?*const anyopaque, action: *const fn (?*const anyopaque, VISIT, c_int) callconv(.c) void) callconv(.c) void {
    twalk_recurse(@constCast(root), action, 0);
}

fn twalk_recurse(p: ?*anyopaque, action: *const fn (?*const anyopaque, VISIT, c_int) callconv(.c) void, depth: c_int) void {
    const node = treeNodeFromPtr(p) orelse return;
    const r: *const anyopaque = @ptrCast(node);
    if (node.a[0] == null and node.a[1] == null) {
        action(r, .leaf, depth);
    } else {
        action(r, .preorder, depth);
        twalk_recurse(node.a[0], action, depth + 1);
        action(r, .postorder, depth);
        twalk_recurse(node.a[1], action, depth + 1);
        action(r, .endorder, depth);
    }
}

// ── Linear Search (lsearch / lfind) ─────────────────────────────────

fn lsearchImpl(key: ?*const anyopaque, base: ?*anyopaque, nelp: *usize, width: usize, compar: ComparFn) callconv(.c) ?*anyopaque {
    const base_bytes: [*]u8 = @ptrCast(base orelse return null);
    const key_bytes: [*]const u8 = @ptrCast(key orelse return null);
    const nel = nelp.*;
    for (0..nel) |i| {
        const elem: *anyopaque = @ptrCast(base_bytes + i * width);
        if (compar(key, elem) == 0) return elem;
    }
    // Not found — append key.
    const dest = base_bytes + nel * width;
    @memcpy(dest[0..width], key_bytes[0..width]);
    nelp.* = nel + 1;
    return @ptrCast(dest);
}

fn lfindImpl(key: ?*const anyopaque, base: ?*const anyopaque, nelp: *usize, width: usize, compar: ComparFn) callconv(.c) ?*anyopaque {
    const base_bytes: [*]const u8 = @ptrCast(base orelse return null);
    const nel = nelp.*;
    for (0..nel) |i| {
        const elem_ptr = base_bytes + i * width;
        // lfind compares with a mutable pointer cast, matching C semantics.
        const elem: *anyopaque = @constCast(@ptrCast(elem_ptr));
        if (compar(key, elem) == 0) return elem;
    }
    return null;
}

// ── Hash Table (hcreate / hdestroy / hsearch and _r variants) ────────

const ENTRY = extern struct {
    key: ?[*:0]u8,
    data: ?*anyopaque,
};

const ACTION = enum(c_int) { FIND = 0, ENTER = 1 };

const Tab = extern struct {
    entries: ?[*]ENTRY,
    mask: usize,
    used: usize,
};

const HSearchData = extern struct {
    tab: ?*Tab,
    unused1: c_uint = 0,
    unused2: c_uint = 0,
};

const MINSIZE: usize = 8;
const MAXSIZE: usize = @as(usize, 1) << (@bitSizeOf(usize) - 1);

var htab_global: HSearchData = .{ .tab = null };

fn keyhash(key_ptr: [*:0]const u8) usize {
    var h: usize = 0;
    var p = key_ptr;
    while (p[0] != 0) {
        h = h *% 31 +% p[0];
        p += 1;
    }
    return h;
}

fn streq(a: [*:0]const u8, b: [*:0]const u8) bool {
    var i: usize = 0;
    while (true) : (i += 1) {
        if (a[i] != b[i]) return false;
        if (a[i] == 0) return true;
    }
}

fn resize(tab: *Tab, nel: usize) bool {
    var new_size: usize = MINSIZE;
    while (new_size < nel) {
        if (new_size >= MAXSIZE) {
            // Cannot grow further.
            return false;
        }
        new_size *= 2;
    }
    const new_entries: ?[*]ENTRY = @ptrCast(@alignCast(std.c.calloc(@sizeOf(ENTRY), new_size)));
    if (new_entries == null) return false;
    const old_entries = tab.entries;
    const old_mask = tab.mask;
    tab.entries = new_entries;
    tab.mask = new_size - 1;
    if (old_entries) |old| {
        // Rehash existing entries.
        if (old_mask > 0) {
            for (0..old_mask + 1) |i| {
                if (old[i].key) |k| {
                    var h = keyhash(k) & tab.mask;
                    while (tab.entries.?[h].key != null) {
                        h = (h + 1) & tab.mask; // linear probe during resize is fine
                    }
                    tab.entries.?[h] = old[i];
                }
            }
        }
        std.c.free(@ptrCast(old));
    }
    return true;
}

fn hcreate_rImpl(nel: usize, htab: *HSearchData) callconv(.c) c_int {
    const tab_ptr: ?*Tab = @ptrCast(@alignCast(std.c.malloc(@sizeOf(Tab))));
    if (tab_ptr == null) return 0;
    const tab = tab_ptr.?;
    tab.entries = null;
    tab.mask = 0;
    tab.used = 0;
    if (!resize(tab, nel)) {
        std.c.free(@ptrCast(tab));
        return 0;
    }
    htab.tab = tab;
    return 1;
}

fn hdestroy_rImpl(htab: *HSearchData) callconv(.c) void {
    if (htab.tab) |tab| {
        if (tab.entries) |entries| {
            std.c.free(@ptrCast(entries));
        }
        std.c.free(@ptrCast(tab));
        htab.tab = null;
    }
}

fn hsearch_rImpl(item: ENTRY, action: ACTION, retval: *?*ENTRY, htab: *HSearchData) callconv(.c) c_int {
    const tab = htab.tab orelse return 0;
    const entries = tab.entries orelse return 0;
    const key = item.key orelse return 0;
    const h = keyhash(key);
    var i = h & tab.mask;

    // Quadratic probing for lookup.
    var j: usize = 1;
    while (entries[i].key) |ek| {
        if (streq(ek, key)) {
            retval.* = &entries[i];
            return 1;
        }
        i = (i +% j) & tab.mask;
        j += 1;
    }

    if (action == .FIND) {
        retval.* = null;
        return 0;
    }

    // ENTER — check load factor and resize if needed.
    if (tab.used + 1 > tab.mask - tab.mask / 4) {
        if (!resize(tab, 2 * tab.used)) {
            retval.* = null;
            return 0;
        }
        // Re-probe after resize.
        i = h & tab.mask;
        j = 1;
        while (tab.entries.?[i].key != null) {
            i = (i +% j) & tab.mask;
            j += 1;
        }
    }
    tab.entries.?[i] = item;
    tab.used += 1;
    retval.* = &tab.entries.?[i];
    return 1;
}

fn hcreateImpl(nel: usize) callconv(.c) c_int {
    return hcreate_rImpl(nel, &htab_global);
}

fn hdestroyImpl() callconv(.c) void {
    hdestroy_rImpl(&htab_global);
}

fn hsearchImpl(item: ENTRY, action: ACTION) callconv(.c) ?*ENTRY {
    var retval: ?*ENTRY = null;
    if (hsearch_rImpl(item, action, &retval, &htab_global) == 0) return null;
    return retval;
}

// ── Tests ────────────────────────────────────────────────────────────

test "insque and remque" {
    var first = Node{ .next = null, .prev = null };
    var second = Node{ .next = null, .prev = null };
    var third = Node{ .next = null, .prev = null };

    insque(&first, null);
    try std.testing.expectEqual(@as(?*Node, null), first.next);
    try std.testing.expectEqual(@as(?*Node, null), first.prev);

    insque(&second, &first);
    try std.testing.expectEqual(@as(?*Node, &second), first.next);
    try std.testing.expectEqual(@as(?*Node, &first), second.prev);

    insque(&third, &first);
    try std.testing.expectEqual(@as(?*Node, &third), first.next);
    try std.testing.expectEqual(@as(?*Node, &second), third.next);
    try std.testing.expectEqual(@as(?*Node, &first), third.prev);
    try std.testing.expectEqual(@as(?*Node, &third), second.prev);

    remque(&third);
    try std.testing.expectEqual(@as(?*Node, &second), first.next);
    try std.testing.expectEqual(@as(?*Node, &first), second.prev);

    remque(&second);
    try std.testing.expectEqual(@as(?*Node, null), first.next);
}

test "tsearch, tfind, and tdelete" {
    if (!builtin.link_libc) return error.SkipZigTest;
    const S = struct {
        fn cmp(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) c_int {
            const va: *const i32 = @ptrCast(@alignCast(a));
            const vb: *const i32 = @ptrCast(@alignCast(b));
            if (va.* < vb.*) return -1;
            if (va.* > vb.*) return 1;
            return 0;
        }
    };

    var root: ?*anyopaque = null;
    const rootp: ?*?*anyopaque = &root;

    var keys = [_]i32{ 5, 3, 7, 1, 4, 6, 8, 2 };

    // Insert all keys.
    for (&keys) |*k| {
        const result = tsearchImpl(@ptrCast(k), rootp, S.cmp);
        try std.testing.expect(result != null);
    }

    // Find all keys.
    for (&keys) |*k| {
        // tfind takes a *const ?*anyopaque
        const const_rootp: ?*const ?*anyopaque = &root;
        const result = tfindImpl(@ptrCast(k), const_rootp, S.cmp);
        try std.testing.expect(result != null);
    }

    // Find non-existent key.
    var missing: i32 = 99;
    {
        const const_rootp: ?*const ?*anyopaque = &root;
        const result = tfindImpl(@ptrCast(&missing), const_rootp, S.cmp);
        try std.testing.expect(result == null);
    }

    // Delete a leaf, an internal node, and the root.
    var del_key: i32 = 2;
    _ = tdeleteImpl(@ptrCast(&del_key), rootp, S.cmp);
    del_key = 3;
    _ = tdeleteImpl(@ptrCast(&del_key), rootp, S.cmp);
    del_key = 5;
    _ = tdeleteImpl(@ptrCast(&del_key), rootp, S.cmp);

    // Verify deleted keys are gone and remaining keys are present.
    {
        const const_rootp: ?*const ?*anyopaque = &root;
        var gone: i32 = 2;
        try std.testing.expect(tfindImpl(@ptrCast(&gone), const_rootp, S.cmp) == null);
        gone = 3;
        try std.testing.expect(tfindImpl(@ptrCast(&gone), const_rootp, S.cmp) == null);
        gone = 5;
        try std.testing.expect(tfindImpl(@ptrCast(&gone), const_rootp, S.cmp) == null);
        var present: i32 = 1;
        try std.testing.expect(tfindImpl(@ptrCast(&present), const_rootp, S.cmp) != null);
        present = 4;
        try std.testing.expect(tfindImpl(@ptrCast(&present), const_rootp, S.cmp) != null);
        present = 7;
        try std.testing.expect(tfindImpl(@ptrCast(&present), const_rootp, S.cmp) != null);
    }

    // Destroy the remaining tree.
    tdestroyImpl(root, null);
}

test "twalk" {
    if (!builtin.link_libc) return error.SkipZigTest;
    const S = struct {
        fn cmp(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) c_int {
            const va: *const i32 = @ptrCast(@alignCast(a));
            const vb: *const i32 = @ptrCast(@alignCast(b));
            if (va.* < vb.*) return -1;
            if (va.* > vb.*) return 1;
            return 0;
        }

        var walk_count: usize = 0;

        fn action(_: ?*const anyopaque, which: VISIT, _: c_int) callconv(.c) void {
            if (which == .postorder or which == .leaf) {
                walk_count += 1;
            }
        }
    };

    var root: ?*anyopaque = null;
    var keys = [_]i32{ 10, 5, 15, 3, 7 };
    for (&keys) |*k| {
        _ = tsearchImpl(@ptrCast(k), @ptrCast(&root), S.cmp);
    }

    S.walk_count = 0;
    twalkImpl(@ptrCast(root), S.action);
    try std.testing.expectEqual(@as(usize, 5), S.walk_count);

    tdestroyImpl(root, null);
}

test "lsearch and lfind" {
    const S = struct {
        fn cmp(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) c_int {
            const va: *const i32 = @ptrCast(@alignCast(a));
            const vb: *const i32 = @ptrCast(@alignCast(b));
            if (va.* == vb.*) return 0;
            return 1;
        }
    };

    var arr: [10]i32 = undefined;
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    var nel: usize = 3;

    // lfind existing.
    var search_key: i32 = 2;
    const found = lfindImpl(@ptrCast(&search_key), @ptrCast(&arr), &nel, @sizeOf(i32), S.cmp);
    try std.testing.expect(found != null);
    const found_val: *const i32 = @ptrCast(@alignCast(found));
    try std.testing.expectEqual(@as(i32, 2), found_val.*);
    try std.testing.expectEqual(@as(usize, 3), nel);

    // lfind missing.
    var missing: i32 = 42;
    const not_found = lfindImpl(@ptrCast(&missing), @ptrCast(&arr), &nel, @sizeOf(i32), S.cmp);
    try std.testing.expect(not_found == null);

    // lsearch inserts missing.
    const inserted = lsearchImpl(@ptrCast(&missing), @ptrCast(&arr), &nel, @sizeOf(i32), S.cmp);
    try std.testing.expect(inserted != null);
    try std.testing.expectEqual(@as(usize, 4), nel);
    try std.testing.expectEqual(@as(i32, 42), arr[3]);
}

test "hsearch" {
    if (!builtin.link_libc) return error.SkipZigTest;
    try std.testing.expect(hcreateImpl(10) != 0);
    defer hdestroyImpl();

    // Insert an entry.
    const result = hsearchImpl(.{ .key = @constCast("hello"), .data = @ptrFromInt(42) }, .ENTER);
    try std.testing.expect(result != null);

    // Find it.
    const found = hsearchImpl(.{ .key = @constCast("hello"), .data = null }, .FIND);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(@as(usize, 42), @intFromPtr(found.?.data));

    // Miss.
    const miss = hsearchImpl(.{ .key = @constCast("world"), .data = null }, .FIND);
    try std.testing.expect(miss == null);
}
