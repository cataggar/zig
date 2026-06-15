---
name: libzigc-release
description: Port the ctaggart/cataggar libzigc (musl-libc-in-Zig) work onto a new Zig base revision and cut a signed `<zig-ver>.libc.N` release in cataggar/zig. Use when asked to rebase libzigc onto a new Zig dev build, run the serial test-libc PR pipeline, or build/sign a libzigc release.
---

# libzigc port + release runbook

How to (1) port the libzigc musl-libc-in-Zig surface onto a new Zig base and (2) cut a signed release in `cataggar/zig`. Distilled from the issue #17 port of `ctaggart/zig@libc/0.16.x` onto Zig `0.17.0-dev.704` (branch `libc17-704`, release `0.17.0-dev.704.libc.1`).

## Repo topology (cataggar/zig)
- **Default branch is `mirror`** — a *workflows-only* branch (`.github/workflows/` + `scripts/`). It exists so `workflow_dispatch` works: **a workflow can only be dispatched via the API/`gh` if the file exists on the default branch.** `gh workflow run X --ref <other>` runs the *definition from `<other>`*, but registration must be on `mirror`.
- `libc/0.16.x` — the upstream libzigc fork (≈444 commits on the 0.16 base). The *source* you port FROM.
- `libc17-704` — the port target (libzigc replayed onto the new Zig base). Branch-protected.
- `gh-release` — holds the publish/mirror tooling history (mirrors official ziglang.org releases via `scripts/{download_assets,check_zig_release}.py` + `publish.yml`/`check-release.yml`). Those workflows + scripts now live on `mirror`.
- `master` — upstream Zig mirror.

## Constraints (hard)
- **PRs merge SERIALLY**, one phase at a time, CI-gated by `test-libc.yml`.
- The pipeline is **strictly serial** — keep one phase PR open at a time; do not run parallel git-mutating automation against a shared checkout.
- **NEVER** open PRs/issues/comments on codeberg `ziglang/zig`. All work stays in cataggar/ctaggart forks (the Zig project bans AI contributions).
- Git trailer on every commit: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.

## The serial port pipeline
Break the diff `git log <oldbase>..origin/libc/0.16.x` into phases by file domain (foundation, stdio, math, time, process, signal, env/inittls, fenv, thread/ldso/setjmp, legacy/exit, windows/wasi, then a deferred-consolidation backlog). For each phase:
1. Branch `libc17-704-<phase>` off fresh `origin/libc17-704`.
2. **Align each `lib/c/*.zig` with the FORK's exact version** (`git show origin/libc/0.16.x:lib/c/<m>.zig`), adapting only for genuine 0.17 drift. Do NOT hand-reconstruct logic (introduces subtle ReleaseSmall-only bugs).
3. Comment out the matching `src/libs/musl.zig` `.c`/`.s` entries (only the symbols you actually ported).
4. Verify locally (see below), open a PR → `libc17-704`, trigger CI, merge only when green + previous phase merged.

### CI dispatch (REQUIRED inputs)
```
gh workflow run test-libc.yml --repo cataggar/zig --ref <branch> -f branch=<branch> -f test-filter=all -f targets=all
```
- Matrix = `build stage4` + 9 arches: x86_64, x86, aarch64, arm, thumb, riscv, powerpc, s390x, wasm32. **loongarch64 is excluded** (LLVM 22 backend regression).
- Merge gate = `mergeStateStatus=CLEAN` (covers test-libc + the `check_musl_migration.py` lint). A *valid* green run must have run ALL targets — verify jobs didn't "Skip" via the target filter.
- `build stage4` runs first (~30 min); the per-arch jobs (several under qemu) are gated behind it and are slow. Runs can queue waiting for a runner.

### Local verification recipe (per phase, before pushing)
- **Migration lint:** `python3 scripts/check_musl_migration.py` must print OK (verifies every commented-out `musl.zig` entry's symbols are exported under `lib/c`).
- **Fast cross-arch compile-check** (catches arch-specific compile errors x86_64-only testing misses): build a `-lc` exe for all 21 non-loongarch triples × Debug/ReleaseFast/ReleaseSmall with the prebuilt host zig against modified `lib/`. ReleaseSmall is mandatory — it surfaces bugs other modes hide.
- **Full runtime:** `stage4/bin/zig build test-libc-nsz --zig-lib-dir lib -Dlibc-test-path=$HOME/libc-test -Dtest-filter=all -Dtest-target-filter=<triple> --summary all` across modes; spot-check non-native arches with `-fqemu` / `-fwasmtime`.

## ⚠️ stage4 dogfoods libzigc (the recurring hazard)
The Zig compiler (stage4) is itself linked against `lib/c` AND runs multithreaded. A buggy ported function that the compiler uses breaks the BUILD with cryptic errors:
- `realpath`→`execve("")`→`posix_spawn failed`; `sysconf(_SC_ARG_MAX)`→corrupt cc1 `@response` file; `__clone`/pthread→`thread constructor failed: EAGAIN` / `mutex lock failed` / `condition_variable wait failed`.
- **The futex cluster (pthread_mutex/cond + __lock + lock_ptc) and pthread_create/join/cancel core are stage4-critical** — verify by building stage4 FROM the branch, then a threaded `zig build test-libc-nsz ... -j8` run 2-3× (no abort), plus a cross-asm `zig build-exe a.c -lc -target x86-linux-musl` (spawns cc1 to assemble musl `.S`). Host-zig checks do NOT catch these. When in doubt keep these musl C.

## Other gotchas learned
- **Cancellation points** (nanosleep/clock_nanosleep/wait*/system/sigsuspend/sigwait*/pause) must stay musl C until the Zig cancellation core (`__syscall_cp` + SIGCANCEL handler) lands — a plain Zig version breaks `functional.pthread_cancel`.
- **f64 long double arches** (powerpc/arm/thumb/wasm): `*l` math fns delegating to std `math.*` can diverge ≥1 ulp from musl under powerpc soft-float ReleaseSmall. Fix with strict f64 paths (compute in f128, round once) — not `@setFloatMode` on a non-inlined std call.
- **va_list / `@cVaArg` is broken on 0.17 for aarch64 (LLVM VaList disabled) and s390x (LLVM abort)** — vfprintf/vfscanf family + execl* stay musl C on those arches.
- **WASI uses the separate `wasi_libc.zig` C build**, not libzigc. Route wasm through libzigc via `wantsZigC` + `_ = @import("c/<m>.zig")` in the `isWasiLibC()` block of `lib/c.zig`. The fork imports multibyte/locale ONLY in the musl block — its `currentUtf8()` uses a portable `setlocale(0,null)` check, not the musl pthread-locale-offset hack (which returns false on wasi → single-byte mode → mbrtowc bugs).
- **extern struct {u32}-by-value ABI** is broken on aarch64/powerpc in 0.16/0.17 (inet_ntoa etc.) — use a `u32` param + inline asm to read the register, or keep musl C.

## Release process (p14)
1. Tag the merged tip: `git tag -a <zig-ver>.libc.N <sha> -m "..."` then `git push origin <tag>`.
2. **Ensure `build-release.yml` is on the default branch `mirror`** (else `workflow_dispatch` 404s). Register via API if missing: `gh api --method PUT repos/cataggar/zig/contents/.github/workflows/build-release.yml -f message=... -f content=<b64> -f branch=mirror`.
3. Dispatch: `gh workflow run build-release.yml --repo cataggar/zig --ref libc17-704 -f tag=<tag>`. It builds stage4 for x86_64-linux (tar.xz), aarch64-macos (tar.xz), x86_64-windows (zip) on GitHub-hosted runners, then signs and uploads.
4. **Signing needs repo secrets `MINISIGN_SECRET_KEY` + `MINISIGN_PASSWORD`** (minisign, via `scripts/sign-asset.exp`). If absent the `attach assets to release` job fails with `minisign exited before prompting for a password`. Only a human with the private key can set them: `gh secret set MINISIGN_SECRET_KEY --repo cataggar/zig`. Public key: `RWQhfv+qEYWFiUiUqTeTGnyN3KQlTSVNpqhCST5HbBKZRi6SfCJhnVF4`.
5. The workflow auto-creates the prerelease and uploads `.tar.xz`/`.zip`/`.minisig` only — **NO `.sha256`** sidecars.
6. Verify assets, then confirm `ghr install cataggar/zig@<tag> RWQhfv+qEYWFiUiUqTeTGnyN3KQlTSVNpqhCST5HbBKZRi6SfCJhnVF4`.

## Parity audit (vs fork)
`git show origin/libc17-704:src/libs/musl.zig | grep '"musl/' | grep -v '//' | sort -u` vs the same on `origin/libc/0.16.x`; `comm`/per-dir net counts show which `.c` files the fork migrated that the port still keeps as musl C. Hard residuals (va_list aarch64/s390x, futex/cancel thread core, some ld80 transcendentals, locale) may be accepted documented gaps.
