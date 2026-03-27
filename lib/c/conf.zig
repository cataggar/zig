const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.link_libc) {
        symbol(&get_nprocs_conf, "get_nprocs_conf");
        symbol(&get_nprocs, "get_nprocs");
        symbol(&get_phys_pages, "get_phys_pages");
        symbol(&get_avphys_pages, "get_avphys_pages");
    }
}

extern "c" fn sysconf(name: c_int) c_long;

const _SC_NPROCESSORS_CONF = 83;
const _SC_NPROCESSORS_ONLN = 84;
const _SC_PHYS_PAGES = 85;
const _SC_AVPHYS_PAGES = 86;

fn get_nprocs_conf() callconv(.c) c_int {
    return @intCast(sysconf(_SC_NPROCESSORS_CONF));
}

fn get_nprocs() callconv(.c) c_int {
    return @intCast(sysconf(_SC_NPROCESSORS_ONLN));
}

fn get_phys_pages() callconv(.c) c_long {
    return sysconf(_SC_PHYS_PAGES);
}

fn get_avphys_pages() callconv(.c) c_long {
    return sysconf(_SC_AVPHYS_PAGES);
}
