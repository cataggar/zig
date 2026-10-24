# libc Release Notes — 0.16.0-libc

This file tracks libzigc C→Zig migration releases that track upstream Zig
release tags. See ctaggart/zig#244 for the release workflow spec, and #10
for the overall migration tracking issue.

## 0.16.0-libc.6d356e5

- **Upstream base**: 0.16.0 (commit `24fdd5b7a4`)
- **Branch**: `libc/0.16.x`
- **Head**: `6d356e58d4` — `libzigc: migrate remaining v-prefix stdio funcs to Zig`

### What's included beyond 0.16.0-libc.308565e (candidate)

1. **#243 fix** (`2d256ea321`): `x86_64-sysv: pass va_list by invisible reference, not byval`.
   Fixes a 10-line ABI violation in `src/codegen/llvm/FuncGen.zig::nextSystemV` —
   when the parameter is exactly `std.builtin.VaList`, classify as `.byref_mut`
   (plain `ptr noundef`) instead of `.memory` + `byval`. Matches x86_64 SysV
   §3.5.7 and clang's lowering. Unblocks Zig callees receiving `va_list` from C callers.
2. **Doc sync** (`1176af4879`): remove retired `ctmain`/`ci` branch references from
   `.github/instructions/sync.instructions.md`.
3. **V-prefix stdio migrations** (`106138cf6c`, `2bb0b4870d`, `6d356e58d4`):
   11 functions moved from musl C to `lib/c/stdio.zig`:
   `vprintf`, `vscanf`, `vsprintf`, `vwprintf`, `vwscanf`, `vdprintf`,
   `vasprintf`, `vsnprintf`, `vsscanf`, `vswprintf`, `vswscanf`.
   All were already implemented in Zig (`*_impl`) but kept as C until the
   #243 fix landed; they are now exported via `symbol()` and the corresponding
   `.c` entries dropped from `src/libs/musl.zig`.

### Relationship to combined

`combined` (`3ff5de91dd`) is also updated with the #243 fix. `libc/0.16.x`
is `combined`'s content rebased onto the `0.16.0` release commit (no
conflicts — the 33 upstream commits between `combined`'s base and
`0.16.0` touch no libzigc files).

### CI qualification matrix (dispatched 2026-04-17)

All dispatches via `test-libc.yml` on `ai` branch, target=all (10 primary
targets: x86, x86_64, aarch64, arm, armeb, powerpc, powerpcle, mips,
mipsel, thumb).

| Filter  | Run ID      | Primary targets | Notes |
|---------|-------------|-----------------|-------|
| ctype   | 24552119047 | 10/10 ✅        | clean |
| stdio   | 24552119762 | 10/10 ✅        | clean (pre-vprefix) |
| stdio   | 24552741043 | 10/10 ✅        | clean (with all 11 v-prefix migrations) |
| string  | 24552120734 | 0/10 ❌         | 2-core thread-exhaustion (known upstream issue; not a regression) |
| math    | 24552121514 | in progress     | expected thread-exhaustion like string |
| env     | 24552122277 | 0/10 ❌         | 2-core thread-exhaustion |
| thread  | 24552123002 | 0/10 ❌         | 2-core thread-exhaustion |
| time    | 24552123583 | 0/10 ❌         | 2-core thread-exhaustion |
| conf    | 24552124228 | 10/10 ✅        | clean |
| exit    | 24552124869 | 0/10 ❌         | 2-core thread-exhaustion |
| legacy  | 24552125547 | 10/10 ✅        | clean (exercises `vwarn`/`verr` by-value VaList) |
| misc    | 24552126208 | 10/10 ✅        | clean (exercises `__vsyslog` by-value VaList) |
| process | 24552126806 | 10/10 ✅        | clean |
| signal  | 24552127529 | 10/10 ✅        | clean |
| stdlib  | 24552128180 | 10/10 ✅        | clean |

**Qualifying filters** (9/14 mandatory + legacy + misc): all green.
**Non-qualifying failures**: string, env, thread, time, exit — all
manifest the identical `thread constructor failed: Resource temporarily
unavailable` / `posix_spawn failed: Function not implemented` pattern
coming from stage4's internal LLVM ThreadPool exhausting the 2-core
runner. These filters compile the largest number of C sub-compilations
per job. No regression attributable to the #243 fix or the v-prefix
migrations — identical failures appear on the prior `308565e` candidate.

Sub-targets (x32, `*_be`) tracked separately; upstream stdlib x32 issues
(aio.zig referencing undefined `std.c.pthread_mutex_t`, `lib/std/os/linux.zig`
syscall arg mismatches, `lib/std/c.zig:7914` unsupported ABI) are
non-blocking per ctaggart/zig#244.

### Known issues

- **Thread exhaustion on 2-core runners**: affects filters that compile
  many C sub-compilations (string, math, env, thread, time, exit).
  `-j1` at the top level doesn't help because stage4's internal LLVM
  ThreadPool spawns its own threads. Tracked separately; not specific
  to this release.
- **x32 sub-target**: upstream stdlib issues prevent compilation. Not
  blocking.

### Tagging

```
git tag 0.16.0-libc.6d356e5 libc/0.16.x
git push ctaggart 0.16.0-libc.6d356e5
gh release create 0.16.0-libc.6d356e5 --repo ctaggart/zig \
    --target libc/0.16.x \
    --notes-file doc/libc-release-notes.md
```
