# Summary of Code Changes Since Zig 0.17.0

This document catalogs the compiler, linker, standard library, and C library (`lib/c`) changes on the `wazig` branch relative to the Zig 0.17.0 release ([`7647adab80`](https://github.com/cataggar/zig/commit/7647adab80dd088f4de3610fd245915a912eb6ad)). Changes are grouped into self-contained functional areas with their commits, pull requests, and affected files.

---

## 1. WASI Preview 2 (`wasip2`) and Preview 3 (`wasip3`) Target & CLI Plumbing

Adds first-class target definitions and CLI/build-system options for WASI 0.2.x (`wasip2`) and WASI 0.3.0 (`wasip3`) while preserving `wasi` for WASI Preview 1 (`0.1.0`).

### Commits
- [`972540096d`](https://github.com/cataggar/zig/commit/972540096d9f73403ef65ebde07b7155a326529c) — `std.Target, compiler, std: add wasip2 target plumbing` ([#65](https://github.com/cataggar/zig/pull/65))
- [`318425a3ff`](https://github.com/cataggar/zig/commit/318425a3fff84f9cfba65f821a1fc30151a434ec) — `wasm: wire post-link Component Model pass for wasm32-wasip2` ([#73](https://github.com/cataggar/zig/pull/73))
- [`a61bf2a543`](https://github.com/cataggar/zig/commit/a61bf2a543939f545d3e283205dd3ac0c9a9b2c4) — `wasip2: add wasmtime E2E test suite, CI hardening, and custom WIT reactor fixes` ([#75](https://github.com/cataggar/zig/pull/75))
- [`6385910cfa`](https://github.com/cataggar/zig/commit/6385910cfad4ddc1f4c2de117b49bebbb6ef7fca) — `wasip2: fix path_open mutate-directory flag, fd_renumber preopens, and WIT/cache handling` ([#76](https://github.com/cataggar/zig/pull/76))
- [`2673277472`](https://github.com/cataggar/zig/commit/2673277472fe03b7a55edfa731b74faaa7d439f4) — `Adding wasm32-wasip3 component model` ([#91](https://github.com/cataggar/zig/pull/91))
- [`866cfb988d`](https://github.com/cataggar/zig/commit/866cfb988d70fea6c1192fecc49e72eee54ae379) — `wasm32-wasip3: self-host full Zig compiler as WASI 0.3 component` ([#98](https://github.com/cataggar/zig/pull/98))

### Key Changes
- **OS Tags & Version Ranges**:
  - Adds `.wasip2` (default version range `0.2.0...0.3.0`) and `.wasip3` (default `0.3.0...0.3.0`) to `std.Target.Os.Tag`, along with `Os.Tag.isWasi()` helper.
  - Updates target switch arms across `std.Target`, `src/target.zig`, `src/Compilation.zig`, Aro (`lib/compiler/aro/aro/{Compilation,Target}.zig`), and `lib/std/`.
- **Component Model CLI & Build Options**:
  - Adds `-fwit-path=<path>`, `-fwit-world=<name>`, and `-fwasi-adapter=<path>` to the CLI (`src/main.zig`), `Compilation` (`src/Compilation.zig`, `src/Compilation/Config.zig`), `std.Build.Step.Compile`, and `Maker.Step.Compile`.
  - Tracks WIT inputs and `wasi_adapter_path` in the incremental cache manifest (`Compilation.addNonIncrementalStuffToCacheManifest`).
  - Supports `--test-cmd=<arg>` `=`-delimited flag syntax in `src/main.zig`.
  - Enables `.version_command` and `.env_command` in `src/dev.zig` for `-Ddev=wasm`.

### Affected Files
- `lib/std/Target.zig`, `lib/std/Target/Query.zig`, `lib/std/zig/target.zig`
- `src/target.zig`, `src/Compilation.zig`, `src/Compilation/Config.zig`, `src/main.zig`, `src/dev.zig`
- `lib/std/Build/Step/Compile.zig`, `lib/compiler/Maker/Step/Compile.zig`
- `lib/compiler/aro/aro/Compilation.zig`, `lib/compiler/aro/aro/Target.zig`

---

## 2. WASI Preview 2 (`0.2.6`) and Preview 3 (`0.3.0`) Standard Library & Runtime

Implements the Canonical ABI guest layers for WASI 0.2.6 and WASI 0.3.0, Component Model entrypoints, WASI host compatibility for the Zig compiler/build runner, and WASI thread/allocator hardening.

### Commits
- [`07211345ba`](https://github.com/cataggar/zig/commit/07211345ba2271583ef12eed51d8b9b95fa273b0) — `wasip2: export cabi_realloc and wasi:cli/run@0.2.6#run entrypoint` ([#68](https://github.com/cataggar/zig/pull/68))
- [`7abd11848b`](https://github.com/cataggar/zig/commit/7abd11848bae3c2e90e6b67ae6fa2d6eb3449370) — `std.os.wasi: add WASI 0.2.6 canonical ABI layer for wasip2` ([#71](https://github.com/cataggar/zig/pull/71))
- [`318425a3ff`](https://github.com/cataggar/zig/commit/318425a3fff84f9cfba65f821a1fc30151a434ec) — `wasm: wire post-link Component Model pass for wasm32-wasip2` ([#73](https://github.com/cataggar/zig/pull/73))
- [`6385910cfa`](https://github.com/cataggar/zig/commit/6385910cfad4ddc1f4c2de117b49bebbb6ef7fca) — `wasip2: fix path_open mutate-directory flag, fd_renumber preopens, and WIT/cache handling` ([#76](https://github.com/cataggar/zig/pull/76))
- [`2673277472`](https://github.com/cataggar/zig/commit/2673277472fe03b7a55edfa731b74faaa7d439f4) — `Adding wasm32-wasip3 component model` ([#91](https://github.com/cataggar/zig/pull/91))
- [`29fa659ca2`](https://github.com/cataggar/zig/commit/29fa659ca221a3e9127fe7ab4e8470f420a8b543) — `aarch64, wasip3: fix self-hosted backend for compiler_rt/Maker and wasip3 exit codes` ([#92](https://github.com/cataggar/zig/issues/92), [#93](https://github.com/cataggar/zig/pull/93))
- [`866cfb988d`](https://github.com/cataggar/zig/commit/866cfb988d70fea6c1192fecc49e72eee54ae379) — `wasm32-wasip3: self-host full Zig compiler as WASI 0.3 component` ([#98](https://github.com/cataggar/zig/pull/98))
- [`50f27c1ed7`](https://github.com/cataggar/zig/commit/50f27c1ed772ebe565b67b7090b5f47d95f149e2) — `std.posix, Io.Threaded: stub freestanding system declarations` ([#101](https://github.com/cataggar/zig/pull/101))
- [`3ea8d8af26`](https://github.com/cataggar/zig/commit/3ea8d8af26faf23a02d052ce8ad9219c222d39de) — `std.heap: support multi-threaded WebAssembly in BrkAllocator` ([#102](https://github.com/cataggar/zig/pull/102))
- [`28de97fbd8`](https://github.com/cataggar/zig/commit/28de97fbd890857261e9c5557d5202f6eed98fb3) — `wasm: support wasm64-wasip3 (64-bit Component Model cm64 and WASI 0.3.0)` ([#116](https://github.com/cataggar/zig/pull/116))
- [`20f22e1f0a`](https://github.com/cataggar/zig/commit/20f22e1f0a57f05ac226d60e562ead9ad46ba3ee) — `wasi: support wasm64-wasip3 C/C++, static LLVM, and wazig/wazigl releases` ([#117](https://github.com/cataggar/zig/pull/117))
- [`113621a0c9`](https://github.com/cataggar/zig/commit/113621a0c92a981741a3bc5ac1a28eb95a210354) — `Enable wasm64-wasip3 static LLVM linking for wazigl release` ([#118](https://github.com/cataggar/zig/pull/118))
- [`20b87ed345`](https://github.com/cataggar/zig/commit/20b87ed3452c441da0d4fc90a16be6f2c333d0c3) — `wasi: guard void Child.Term signal/stopped in Build.Serialize and Maker` ([#122](https://github.com/cataggar/zig/pull/122))
- [`866b84dfbf`](https://github.com/cataggar/zig/commit/866b84dfbf162f5254a5752035974069b6eb81e8) — `Fix WASI P2/P3 filestat metadata-hash ino/dev mapping and relativeAppendPosix` ([#123](https://github.com/cataggar/zig/pull/123))
- [`11114d306c`](https://github.com/cataggar/zig/commit/11114d306c87aa9fb7463d85410218d00d4a07f2) — `wasi: harden WasiThreadImpl and support wasm_main_thread_no_wait` ([#126](https://github.com/cataggar/zig/issues/126), [#127](https://github.com/cataggar/zig/issues/127), [#128](https://github.com/cataggar/zig/pull/128))
- [`978c362e39`](https://github.com/cataggar/zig/commit/978c362e39501a0569002452c12ed1aedf50ac9c) — `wasi: run zig translate-c in-process when !std.process.can_spawn` ([#143](https://github.com/cataggar/zig/issues/143), [#146](https://github.com/cataggar/zig/pull/146))
- [`63bc0870ec`](https://github.com/cataggar/zig/commit/63bc0870ec555a7369a659b992160399a780af9b) — `wasi, libc: share wasip3 descriptor table and BrkAllocator state across ZCUs` ([#130](https://github.com/cataggar/zig/issues/130), [#152](https://github.com/cataggar/zig/pull/152))
- [`0937dcb70c`](https://github.com/cataggar/zig/commit/0937dcb70ce2e1f22b91a6d135170e45904e07ce) — `wasm (wasip3 / std.Io): dual-stack __stack_pointer context switching & WasmFX continuations` ([#162](https://github.com/cataggar/zig/issues/162), [#165](https://github.com/cataggar/zig/pull/165))
- [`b23f3693b9`](https://github.com/cataggar/zig/commit/b23f3693b95726384c1ef32b84e0e8e220f8655b) — `wasi / wasm: atomic cache manifest & archive writes and bounds-checked Archive/Object parsing` ([#171](https://github.com/cataggar/zig/issues/171), [#175](https://github.com/cataggar/zig/pull/175))
- [`5339986deb`](https://github.com/cataggar/zig/commit/5339986debd38e563e449d4a6a7cd952dfb3561d) — `std.os.wasi: pool P3 waitable-sets, cache sequential streams, and uncap P2 writes` ([#200](https://github.com/cataggar/zig/issues/200), [#208](https://github.com/cataggar/zig/pull/208))

### Key Changes
- **WASI P2 & P3 I/O and Async Hostcall Fast Paths (`lib/std/os/wasi/p2.zig`, `lib/std/os/wasi/p3.zig`)**:
  - Pools `waitable-set` handles per root task (`State.root_waitable_set`) and per fiber (`TaskContext.waitable_set`) in `p3.zig`, eliminating `waitable-set.new` and `waitable-set.drop` hostcalls on every async `waitReady` and `awaitAsyncCall` while filtering events by waitable handle and unjoining subtasks before drop.
  - Caches sequential `read_stream` and `write_stream` handles and stream byte offsets on `FdEntry` across `p2.zig` and `p3.zig` (and stdio streams on `State` in `p3.zig`), invalidating cached streams only on position-changing `fd_seek`, `fd_close`, `fd_renumber`, `fd_sync`, `fd_datasync`, `fd_filestat_set_size`, `fd_fdstat_set_flags`, or same-handle writes so sequential read/write and file-to-file copy loops reuse stream handles without per-call `[method]descriptor.read-via-stream` / `write-via-stream` / `[resource-drop]` overhead.
  - Uncaps 4 KiB write flush chunks in `p2.zig` `writeOutputStreamIovs`: keeps the single-hostcall `blocking-write-and-flush` fast path for single-iov writes `<= 4096` bytes and uses `check-write` + `write` up to the full permit with a single trailing `blocking-flush` for larger or multi-iov writes.
- **Component Entrypoints & `cabi_realloc` (`lib/std/start.zig`)**:
  - Exports `wasi:cli/run@0.2.6#run` on `wasip2` and `wasi:cli/run@0.3.0#run` (with `[task-return]` async completion and `proc_exit` propagation for non-zero exit codes) on `wasip3`.
  - Exports `cabi_realloc` backed by `std.heap.wasm_allocator` only when `builtin.output_mode == .Exe` or `(.Lib and .dynamic)` so static archives (`libcompiler_rt.a`) and `.o` objects do not emit duplicate symbols.
- **WASI 0.2.6 Canonical ABI Layer (`lib/std/os/wasi/p2.zig`, `lib/std/os/wasi.zig`)**:
  - Implements WASI 0.2.6 Canonical ABI externs and Preview 1-compatible wrappers for stdio streams, preopens, filesystem descriptors, CLI args/environ, clocks, random, exit, and `poll_oneoff` so non-libc `wasip2` binaries emit zero `wasi_snapshot_preview1` imports.
  - Returns `SPIPE` from `fd_pread`/`fd_pwrite` on stdio descriptors so `std.Io.File.Writer` switches to streaming mode.
  - Sets `descriptor-flags.mutate-directory` (`0x20`) when opening directories or requesting mutating `PATH_*` rights, with a read-only retry fallback; rejects `fd_renumber` on preopen descriptors (`.NOTSUP`).
- **WASI 0.3.0 Canonical ABI Layer (`lib/std/os/wasi/p3.zig`)**:
  - Implements WASI 0.3.0 Canonical ABI bindings for async tasks, `waitable-set`, `stream<u8>`, `future<result>`, clocks, random, CLI, and filesystem across `wasm32-wasip3` and `wasm64-wasip3` (`cm64`).
  - Adds dual-stack `__stack_pointer` context switching (`getStackPointer`/`setStackPointer`, 16-byte-aligned `ShadowStack` with `0xDEAD_BEEF_CAFE_BABE` canary and bounds checks, `ShadowStackPool`, and `TaskContext` with a `noinline` entry trampoline and nested `active_task` binding) for green-thread / fiber suspension across WASI 0.3 async tasks.
- **Filesystem `ino`/`dev` Mapping & Path Resolution (`lib/std/os/wasi/p2.zig`, `lib/std/os/wasi/p3.zig`, `lib/std/fs/path.zig`)**:
  - Maps `metadata-hash-value.upper` to `buf.dev` and `metadata-hash-value.lower` to `buf.ino` (and `d_ino` in `fd_readdir`) instead of `lower ^ upper`, avoiding `(dev, ino)` collisions under Wasmtime's `upper = lower ^ hash(st_dev)`.
  - Fixes `std.fs.path.relativeAppendPosix` when resolving `"."` or empty `cwd` (`""` on WASI) to resize/memmove before writing `"../"` prefixes without slicing out of bounds or clobbering `to_rest`.
  - Resolves leading-`/` paths against longest-prefix named WASI preopens (`resolvePathEntry`, `stripPreopenPrefix`) across all `path_*` functions in `lib/std/os/wasi/p2.zig` and `lib/std/os/wasi/p3.zig` so non-libc WASI binaries (`wazig`) can access `/lib/...` and `/cache/...` paths via `Io.Dir.cwd()`.
- **WASI Host Compiler & Build Runner Support**:
  - Resolves `"."` via `preopens.get(".")` in `src/main.zig` `wasi_cwd()`, allows `"/"` alongside `"."` in `std.zig.getResolvedCwd` on WASI when linked with libc, and falls back to the guest `/lib` preopen when `--zig-lib-dir` / `ZIG_LIB_DIR` are not explicitly set (`lib/std/zig/LibCDirs.zig`, `lib/std/Build/Configuration.zig`).
  - Guards `void` `Child.Term.signal` and `.stopped` payloads (`std.posix.SIG == void` on WASI) in `lib/std/Build/Serialize.zig`, `lib/compiler/Maker/Step/Run.zig`, and `lib/compiler/Maker.zig`.
  - Runs `zig translate-c` in-process via `@import("translate_c").translateInProcess` (`lib/compiler/translate-c/main.zig`, `src/main.zig`, `build.zig`) when `!std.process.can_spawn`, capturing serialized `ErrorBundle` diagnostics under `--zig-integration` without spawning a child process or calling `std.process.exit`.
  - Writes cache manifests atomically via temp file + rename in `Cache.Manifest.finalize` on WASI targets (`lib/std/Build/Cache.zig`) and flushes/closes whole-cache Wasm/WASI outputs in `tmp/<rand>/` before atomically publishing into `o/<digest>/` (`src/Compilation.zig`).
- **Freestanding & Multi-Threaded WebAssembly (`lib/std/posix.zig`, `lib/std/Io/Threaded.zig`, `lib/std/Thread.zig`, `lib/std/heap/BrkAllocator.zig`)**:
  - Stubs missing `posix.system` declarations (`IOV_MAX`, `Sigaction`, `STDIN_FILENO`, `cmsghdr`, `flock`, `getrandom`) and guards `Threaded.NullFile` when `posix.fd_t == void` so `std.Io.Threaded` compiles on `wasm32-freestanding`.
  - Guards `BrkAllocator` (`std.heap.wasm_allocator`) global state with `std.atomic.Mutex` when `!builtin.single_threaded`.
  - Hardens `WasiThreadImpl` (`callconv(.naked)` `wasi_thread_start`, downward-growing stack offset calculation, direct `allocator.vtable.free` on self-stack exit, `cancel`, `__tls_set_base`, default `wasm_allocator`).
  - Adds `std.Options.wasm_main_thread_no_wait` and a race-free main-thread futex spin loop in `std.Io.Threaded` for runtimes that trap `memory.atomic.wait32` on the main thread.

### Affected Files
- `build.zig`, `src/main.zig`, `src/Compilation.zig`, `lib/compiler/translate-c/main.zig`
- `lib/std/start.zig`, `lib/std/os/wasi.zig`, `lib/std/os/wasi/p2.zig`, `lib/std/os/wasi/p3.zig`, `lib/std/posix/wasi.zig`
- `lib/std/fs/path.zig`, `lib/std/zig.zig`, `lib/std/zig/LibCDirs.zig`, `lib/std/Build/Cache.zig`, `lib/std/Build/Configuration.zig`, `lib/std/Build/Serialize.zig`
- `lib/compiler/Maker.zig`, `lib/compiler/Maker/Step.zig`, `lib/compiler/Maker/Step/Run.zig`
- `lib/std/posix.zig`, `lib/std/Io/Threaded.zig`, `lib/std/Thread.zig`, `lib/std/heap.zig`, `lib/std/heap/BrkAllocator.zig`
- `test/wasip2_e2e.zig`, `test/wasip3_e2e.zig`, `lib/std/fs/test.zig`, `lib/std/posix/test.zig`

---

## 3. WebAssembly Codegen, 64-Bit (`wasm64`), Optimizer, and Component Linker

Extends the self-hosted WebAssembly code generator and linker with static archive creation, 64-bit (`memory64` / `cm64`) support, intrafunction MIR and post-link core optimizers, and a built-in Component Model encoder/adapter pipeline.

### Commits
- [`d677b562f3`](https://github.com/cataggar/zig/commit/d677b562f33cdb6c5a6dbd330db157142e262a47) — `wasm: undefined allowed limit only to == .strong`
- [`c36f7cb296`](https://github.com/cataggar/zig/commit/c36f7cb296c6921164989ef56311cbe88d16be38) — `wasm: fix switch on wide integers and ?error repr`
- [`431f39f6ed`](https://github.com/cataggar/zig/commit/431f39f6ed662b5c54157bdc0b02db1548b0eddc) — `wasm: implement static archive`
- [`cee35acdbb`](https://github.com/cataggar/zig/commit/cee35acdbb9ef627085325cb94e1b21817f01b08) — `wasm: fix bool confusion in memset`
- [`96edf41e88`](https://github.com/cataggar/zig/commit/96edf41e88e42216a4669f02a981e2b4f4a2566b) — `wasm: vendor wabt component library for wasm32-wasip2` ([#18](https://github.com/cataggar/zig/issues/18), [#67](https://github.com/cataggar/zig/pull/67))
- [`318425a3ff`](https://github.com/cataggar/zig/commit/318425a3fff84f9cfba65f821a1fc30151a434ec) — `wasm: wire post-link Component Model pass for wasm32-wasip2` ([#73](https://github.com/cataggar/zig/pull/73))
- [`a61bf2a543`](https://github.com/cataggar/zig/commit/a61bf2a543939f545d3e283205dd3ac0c9a9b2c4) — `wasip2: add wasmtime E2E test suite, CI hardening, and custom WIT reactor fixes` ([#75](https://github.com/cataggar/zig/pull/75))
- [`2673277472`](https://github.com/cataggar/zig/commit/2673277472fe03b7a55edfa731b74faaa7d439f4) — `Adding wasm32-wasip3 component model` ([#91](https://github.com/cataggar/zig/pull/91))
- [`866cfb988d`](https://github.com/cataggar/zig/commit/866cfb988d70fea6c1192fecc49e72eee54ae379) — `wasm32-wasip3: self-host full Zig compiler as WASI 0.3 component` ([#98](https://github.com/cataggar/zig/pull/98))
- [`a5633fae06`](https://github.com/cataggar/zig/commit/a5633fae066b597595268b4975b68a74d9a0f330) — `wasm: add MIR peephole optimizer and wabt post-link core optimizer` ([#108](https://github.com/cataggar/zig/pull/108))
- [`28de97fbd8`](https://github.com/cataggar/zig/commit/28de97fbd890857261e9c5557d5202f6eed98fb3) — `wasm: support wasm64-wasip3 (64-bit Component Model cm64 and WASI 0.3.0)` ([#116](https://github.com/cataggar/zig/pull/116))
- [`20f22e1f0a`](https://github.com/cataggar/zig/commit/20f22e1f0a57f05ac226d60e562ead9ad46ba3ee) — `wasi: support wasm64-wasip3 C/C++, static LLVM, and wazig/wazigl releases` ([#117](https://github.com/cataggar/zig/pull/117))
- [`113621a0c9`](https://github.com/cataggar/zig/commit/113621a0c92a981741a3bc5ac1a28eb95a210354) — `Enable wasm64-wasip3 static LLVM linking for wazigl release` ([#118](https://github.com/cataggar/zig/pull/118))
- [`cf63fe3cd2`](https://github.com/cataggar/zig/commit/cf63fe3cd251f56ed0583f1b3e0d9002aecc0a0c) — `stage2_wasm: support multithreaded WASI (TLS, naked callconv, inline asm)` ([#129](https://github.com/cataggar/zig/issues/129), [#135](https://github.com/cataggar/zig/pull/135))
- [`6098d8fb45`](https://github.com/cataggar/zig/commit/6098d8fb458b47c9d348f1012194aae12e90e436) — `wasm: omit unreferenced ZCU functions in Flush and rewrite name section in Optimizer` ([#114](https://github.com/cataggar/zig/issues/114), [#137](https://github.com/cataggar/zig/pull/137))
- [`5cd7a492ff`](https://github.com/cataggar/zig/commit/5cd7a492ff6afebdd66830a8d8b26f710688babf) — `wasm: fold constant address offsets into load/store MemArg.offset` ([#109](https://github.com/cataggar/zig/issues/109), [#138](https://github.com/cataggar/zig/pull/138))
- [`3409952fa8`](https://github.com/cataggar/zig/commit/3409952fa85ecec38d563ef5ee2e6fbd649017eb) — `wasm: elide stack pointer global.set in leaf functions with stack frames` ([#112](https://github.com/cataggar/zig/issues/112), [#139](https://github.com/cataggar/zig/pull/139))
- [`60a4c99d9e`](https://github.com/cataggar/zig/commit/60a4c99d9efe37fc1411bc70a0219ebe5769f76e) — `wasm: recompute mir_uavs after Mir.Optimize to prune dead constants` ([#110](https://github.com/cataggar/zig/issues/110), [#140](https://github.com/cataggar/zig/pull/140))
- [`a99c449c97`](https://github.com/cataggar/zig/commit/a99c449c97272b13d1a719353028334035e4b5f8) — `wasm: compact sparse mir_locals and RLE-encode local declarations` ([#111](https://github.com/cataggar/zig/issues/111), [#141](https://github.com/cataggar/zig/pull/141))
- [`5d003935f2`](https://github.com/cataggar/zig/commit/5d003935f218f6cc12a88e565d6e73cb4c4b4737) — `wasm: add algebraic identity and strength-reduction peepholes to MIR and core optimizers` ([#113](https://github.com/cataggar/zig/issues/113), [#142](https://github.com/cataggar/zig/pull/142))
- [`e00abf8d94`](https://github.com/cataggar/zig/commit/e00abf8d94a2f592de40eab0abbdaadd1ad6a3b5) — `wasm: support --import-table and inline trivial callees for Zigar` ([#145](https://github.com/cataggar/zig/pull/145))
- [`b485eb0d2e`](https://github.com/cataggar/zig/commit/b485eb0d2ed91364fe86bacc16cadd65c16bec03) — `wasm: support global_assembly .globaltype, synthetic --export, and zcu_funcs growth` ([#148](https://github.com/cataggar/zig/pull/148))
- [`26ad4fa011`](https://github.com/cataggar/zig/commit/26ad4fa0116f1e85a9aae68e517f50884c87a9d6) — `wasm: do not fold untyped post-link add into MemArg.offset in Optimizer` ([#151](https://github.com/cataggar/zig/pull/151))
- [`9e85da1fe3`](https://github.com/cataggar/zig/commit/9e85da1fe375075faf7eeb46d9e5f2bc9c3c922a) — `wasm: lower f32/f64 @min/@max and 128-bit integer shifts/muls inline` ([#153](https://github.com/cataggar/zig/issues/153), [#158](https://github.com/cataggar/zig/pull/158))
- [`c2ae621859`](https://github.com/cataggar/zig/commit/c2ae621859d2347a7dff27a5334de10ab6c0b469) — `wasm: implement Scalar Replacement of Aggregates (SROA) to Wasm locals` ([#154](https://github.com/cataggar/zig/issues/154), [#159](https://github.com/cataggar/zig/pull/159))
- [`19af0fb110`](https://github.com/cataggar/zig/commit/19af0fb11039a22ab02d23bd7e4623f611dcce87) — `wasm: extend Optimizer.zig leaf inlining and local peephole passes` ([#155](https://github.com/cataggar/zig/issues/155), [#163](https://github.com/cataggar/zig/pull/163))
- [`cd54e67ea6`](https://github.com/cataggar/zig/commit/cd54e67ea6f0de207e9510b05967e635aae1853b) — `wasm: fix @Vector constant layout and implement v128 SIMD arithmetic` ([#156](https://github.com/cataggar/zig/issues/156), [#164](https://github.com/cataggar/zig/pull/164))
- [`0937dcb70c`](https://github.com/cataggar/zig/commit/0937dcb70ce2e1f22b91a6d135170e45904e07ce) — `wasm (wasip3 / std.Io): dual-stack __stack_pointer context switching & WasmFX continuations` ([#162](https://github.com/cataggar/zig/issues/162), [#165](https://github.com/cataggar/zig/pull/165))
- [`326ae69b00`](https://github.com/cataggar/zig/commit/326ae69b003ea6560ced0ec0806547d475eb2cba) — `wasm: fix --export=__stack_pointer dropped when objects import __stack_pointer` ([#161](https://github.com/cataggar/zig/issues/161), [#166](https://github.com/cataggar/zig/pull/166))
- [`25bcd82e14`](https://github.com/cataggar/zig/commit/25bcd82e14b51af5f9fe0f533530174b77f1fd0a) — `wasm: export __stack_pointer by default for -rdynamic, reactor, and WASI P3 builds` ([#160](https://github.com/cataggar/zig/issues/160), [#167](https://github.com/cataggar/zig/pull/167))
- [`d4559da5b4`](https://github.com/cataggar/zig/commit/d4559da5b412b597bfa4e921abdddbb2f095d9a9) — `wasm: Optimizer.zig .small single-caller/1-local and .fast 1-cold-call inlining` ([#169](https://github.com/cataggar/zig/issues/169), [#172](https://github.com/cataggar/zig/pull/172))
- [`b8f1719f90`](https://github.com/cataggar/zig/commit/b8f1719f906c27070da6d86c05be38adfeb05574) — `wasm: SIMD @reduce and fused cmp_vector + @reduce(.And/.Or) lowering` ([#168](https://github.com/cataggar/zig/issues/168), [#173](https://github.com/cataggar/zig/pull/173))
- [`35faca1170`](https://github.com/cataggar/zig/commit/35faca1170abd7bcc23d6a6ed152de1b9e43beb7) — `wasm: return small 1-scalar and 2-scalar aggregates by value in .auto CC` ([#170](https://github.com/cataggar/zig/issues/170), [#174](https://github.com/cataggar/zig/pull/174))
- [`b23f3693b9`](https://github.com/cataggar/zig/commit/b23f3693b95726384c1ef32b84e0e8e220f8655b) — `wasi / wasm: atomic cache manifest & archive writes and bounds-checked Archive/Object parsing` ([#171](https://github.com/cataggar/zig/issues/171), [#175](https://github.com/cataggar/zig/pull/175))
- [`5dffe14ecd`](https://github.com/cataggar/zig/commit/5dffe14ecd5e9fb7ea9c6d7acd9501884ba0ed1e) — `std.mem.swap: avoid runtime byte-by-byte loop for small types` ([#179](https://github.com/cataggar/zig/issues/179), [#185](https://github.com/cataggar/zig/pull/185))
- [`f91b522017`](https://github.com/cataggar/zig/commit/f91b522017c6e184e82a96a9e99d953e6583f501) — `wasm: Optimizer.zig leaf/caller stack-copy DCE, 0xfc deltas, 2-result & post-early-return inlining, .small 12-op cap` ([#180](https://github.com/cataggar/zig/issues/180), [#183](https://github.com/cataggar/zig/issues/183), [#186](https://github.com/cataggar/zig/pull/186))
- [`a8663a7fbb`](https://github.com/cataggar/zig/commit/a8663a7fbb6afc9fdf19789a38de8c7d26146de8) — `wasm: elide unread SROA field loads, bitcast byte-array copies, and readonly alloc copies` ([#181](https://github.com/cataggar/zig/issues/181), [#187](https://github.com/cataggar/zig/pull/187))
- [`1820f5885e`](https://github.com/cataggar/zig/commit/1820f5885eb2c180207593c218249a5775f74417) — `wasm: extend .auto scalar returns to error_union/optional/slice and pass <=4-scalar params by value` ([#182](https://github.com/cataggar/zig/issues/182), [#188](https://github.com/cataggar/zig/pull/188))
- [`ea369c6b20`](https://github.com/cataggar/zig/commit/ea369c6b20d425766022b0f10a68d5653ea69339) — `wasm: Optimizer.zig track depth-0 stack deltas for 0xfd SIMD instructions` ([#189](https://github.com/cataggar/zig/issues/189), [#193](https://github.com/cataggar/zig/pull/193))
- [`4224f03f55`](https://github.com/cataggar/zig/commit/4224f03f55076ab78d65e224a8024c4b377c8eed) — `wasm: support vector_index lane accesses in SROA and readonly alloc alias` ([#190](https://github.com/cataggar/zig/issues/190), [#194](https://github.com/cataggar/zig/pull/194))
- [`a85ac40bc3`](https://github.com/cataggar/zig/commit/a85ac40bc30f7f323b3431d1d4d15e6e4bbecc98) — `wasm: Optimizer.zig post-inlining shadow-stack slot scalarization (SROA)` ([#191](https://github.com/cataggar/zig/issues/191), [#195](https://github.com/cataggar/zig/pull/195))
- [`b727795437`](https://github.com/cataggar/zig/commit/b7277954372cfaf0a85892b05589c6b85a6593c3) — `wasm: avoid SROA over-promotion of large copy-modify-pass aggregates` ([#192](https://github.com/cataggar/zig/issues/192), [#196](https://github.com/cataggar/zig/pull/196))
- [`3a7906cecc`](https://github.com/cataggar/zig/commit/3a7906cecca674a8c172b61338a07fac39ef9098) — `wasm(Optimize): loop/block local preservation & LICM, intra-block memory forwarding/DSE, and strength reductions` ([#197](https://github.com/cataggar/zig/issues/197), [#198](https://github.com/cataggar/zig/issues/198), [#199](https://github.com/cataggar/zig/issues/199), [#209](https://github.com/cataggar/zig/pull/209))
- [`ab9f3a705d`](https://github.com/cataggar/zig/commit/ab9f3a705d9a284d87e46e8b6ea7bdc95efdfede) — `wasm(Optimizer): add LICM, store/load forwarding & DSE, strength reduction, and 2-pass inlining` ([#197](https://github.com/cataggar/zig/issues/197), [#198](https://github.com/cataggar/zig/issues/198), [#199](https://github.com/cataggar/zig/issues/199), [#206](https://github.com/cataggar/zig/issues/206), [#214](https://github.com/cataggar/zig/pull/214))
- [`e40a592d8b`](https://github.com/cataggar/zig/commit/e40a592d8bcf57e5cb8fc3fc7ca038fb4810ca11) — `wasm: unroll small fixed-size memcpy, lower SIMD @min/@max via pmin/pmax, u128 SROA, Wyhash fast path, and subblock load elision` ([#204](https://github.com/cataggar/zig/issues/204), [#205](https://github.com/cataggar/zig/issues/205), [#206](https://github.com/cataggar/zig/issues/206), [#207](https://github.com/cataggar/zig/issues/207), [#212](https://github.com/cataggar/zig/pull/212))
- [`80a3942e81`](https://github.com/cataggar/zig/commit/80a3942e81a86bfb4586fbe9339244d19a43ec4e) — `wasm: elide unchecked undef stores/memset, unreachable branches, and single-exit blocks; inline activeTag` ([#213](https://github.com/cataggar/zig/issues/213), [#215](https://github.com/cataggar/zig/issues/215), [#216](https://github.com/cataggar/zig/issues/216), [#217](https://github.com/cataggar/zig/issues/217), [#220](https://github.com/cataggar/zig/pull/220))
- [`8487cbe09c`](https://github.com/cataggar/zig/commit/8487cbe09c648a2546a08f294d7d85c4fd2eba54) — `wasm: inline all-zero >16B constant stores and forward slice coercions in SROA` ([#218](https://github.com/cataggar/zig/issues/218), [#222](https://github.com/cataggar/zig/pull/222))
- [`21aeb5fcc5`](https://github.com/cataggar/zig/commit/21aeb5fcc5fa296263a2cb438f68a77612ef632a) — `wasm: close ReleaseFast (+simd128) runtime gap via multivalue ABI, copy elision, and Optimizer passes` ([#223](https://github.com/cataggar/zig/issues/223), [#224](https://github.com/cataggar/zig/pull/224))

### Key Changes
- **Core Wasm Codegen & Linker Fixes (`src/codegen/wasm/`, `src/link/Wasm.zig`, `src/link/Wasm/`)**:
  - Implements static archive (`.a`) creation and extraction in `src/link/Wasm/Archive.zig` and `src/link/Wasm/Flush.zig`, and bounds-checks `Archive.parse`, `Archive.parseObject`, `Archive.Builder.collectSymbols`, and `Object.parse` with 32-bit overflow-safe arithmetic so empty or truncated archives/objects return `error.BadArchiveMagic` / `error.BadObjectMagic` instead of panicking.
  - Fixes `switch` lowering on wide integers, optional error (`?error`) representation, and `bool` operand lowering in `memset` (`src/codegen/wasm/CodeGen.zig`).
  - Restricts undefined-symbol allowance to `.strong` symbols, maps `extern "c"` symbols to the `.none` import module so weak ZCU definitions do not clobber strong C symbols, fixes weak indirect function table entries, and preserves the `target_features` custom section on stripped relocatable objects.
  - Guards `SymbolFlags.isIncluded` with `!flags.undefined` for `-rdynamic`, skips `module_name` mismatch errors on already-resolved symbols in `Object.zig`, preserves shared unresolved WASI imports across ZCU and archive objects in `Flush.zig`, and gives strong ZCU exports precedence over weak archive symbols.
  - Supports multithreaded WebAssembly (`+atomics+bulk_memory`) in the self-hosted Wasm backend and linker: `threadlocal` variables (`__tls_base`, `__tls_size`, `__tls_align`, `R_WASM_MEMORY_ADDR_TLS_SLEB`), `.naked` calling convention, inline Wasm assembly (`local.get`/`global.set`), passive data segments (`datacount` section, atomic `__wasm_init_memory`, and `__wasm_init_tls` via `memory.init`), and shared imported memory export handling.
  - Folds constant address offsets from `ptr_add`, `struct_field_ptr*`, and integer `add` chains directly into Wasm load/store `MemArg.offset` (`src/codegen/wasm/CodeGen.zig`), and run-length encodes local declarations in `src/codegen/wasm/Emit.zig`.
  - Performs a pre-emission reachability walk in `src/link/Wasm/Flush.zig` (`markZcuNavReachable`, `markZcuUavReachable`) to omit unreferenced ZCU functions before emitting code sections, implements `--import-table` (`options.import_table`) to emit `env.__indirect_function_table` in the `Import` section with `limits.min = entries + 1` and active `Element` initialization while omitting a local `Table` definition, and emits exported function symbol names in the `name` custom section.
  - Parses top-level `.globaltype <name>, <valtype>[, immutable]` directives from `Zcu.global_assembly` into `Wasm.asm_globals` so module-local WebAssembly globals accessed via inline `global.get`/`global.set` are emitted in the `Global` section, resolves explicit `--export=<name>` flags for synthetic linker globals (`__stack_pointer`, `__heap_base`, `__heap_end`, `__tls_base`, `__tls_size`, `__tls_align`, and `asm_globals`, including when input relocatable objects or archives also import `env.<global>`) and synthetic functions (`__wasm_call_ctors`, `__wasm_init_memory`, `__wasm_init_tls`), exports `__stack_pointer` by default (`shouldExportStackPointerForConfig`) for `-rdynamic`, `-mexec-model=reactor`, dynamic WASI libraries, and `wasip3` builds, and indexes `wasm.zcu_funcs` by integer during the intrinsic/tag-name scan in `Flush.finish` so `.call_tag_index` map growth cannot invalidate `keys()`/`values()` slices.
  - Adds the `stack_switching` WebAssembly CPU feature (depending on `exception_handling` and `reference_types`) along with `cont_type` (`0x5d`), `contref` (`0x68`), `nullcontref` (`0x75`), and WasmFX continuation opcodes (`cont.new`, `cont.bind`, `suspend`, `resume`, `resume_throw`, `resume_throw_ref`, `switch` in `0xe0..0xe6`) across `std.wasm`, self-hosted Wasm codegen/inline assembly, and the Wasm component binary reader/writer.
  - Lowers `f32`/`f64` `@min`/`@max` (`floatMin`/`floatMax` with NaN propagation, known-non-NaN `select` fast paths, and `f32x4.pmin`/`f32x4.pmax` / `f64x2.pmin`/`f64x2.pmax` 1-instruction SIMD lowering when an operand is known non-NaN or in `.optimized` float mode) and `65..128`-bit integer shifts (`intShl`/`intShr`) and multiplies (`intMul128` with `isInt128HighZero` specialization and `lllocal` 2x`i64` result storage) inline instead of emitting `compiler_rt` calls.
  - Unrolls fixed-size `memcpy`/`store`/`load` copies (`<= 128` bytes with `+simd128` using `v128.load`/`v128.store` + `i64`/`i32`/`i16`/`i8` tail ops, and `<= 32` bytes without SIMD using `i64.load`/`i64.store` tail ops) with overlap-safe all-loads-before-stores semantics outside `ReleaseSmall`, avoiding out-of-line `memory.copy` libcalls in Wasmtime/Cranelift.
  - Implements Scalar Replacement of Aggregates (SROA) (`SroaAnalysis` in `src/codegen/wasm/CodeGen.zig`, including `65..128`-bit integers as `2 x i64` leaves, `@Vector` lane accesses, and constant `store`/`aggregate_init` preservation), promoting non-escaping aggregate stack slots, aggregate parameters, and by-ref temporaries of up to 16 scalar leaf fields directly to Wasm locals, reusing or extending owned rvalue stack slots in place in `airUnionInit` and `airWrapOptional` (`isOwnedRvalueStackSlot`), eliding unread field loads, optional/union payload copies, rvalue method-call allocs, and read-only `const` aggregate copies (including across `if`/`switch`/`try`/`.block` continuations via `ReadOnlyAllocAliasAnalysis` and `scanBlockForLoadElisions`), and avoiding over-promotion of large copy-modify-pass aggregates ([#223](https://github.com/cataggar/zig/issues/223), [#224](https://github.com/cataggar/zig/pull/224)).
  - Returns small 1- to 4-scalar aggregates (`AutoReturn`, `max_auto_return_scalars = 4`, including `error_union`, `optional`, slices, and 3/4-field structs) by value and passes `<= 4`-scalar aggregates by value in `.auto` calling convention instead of linear-memory `sret`/byref while keeping the `.wasm_mvp` C ABI unchanged ([#182](https://github.com/cataggar/zig/issues/182), [#188](https://github.com/cataggar/zig/pull/188), [#223](https://github.com/cataggar/zig/issues/223), [#224](https://github.com/cataggar/zig/pull/224)).
  - Splits `std.hash.Wyhash.update` into an inlineable `<= 48`-byte fast path and `noinline fn updateCold` (`lib/std/hash/wyhash.zig`), marks `std.meta.activeTag` `inline` (`lib/std/meta.zig`) so callers avoid shadow-stack aggregate copies and read the active union tag directly ([#215](https://github.com/cataggar/zig/issues/215)), and avoids runtime byte-by-byte loops in `std.mem.swap` for small types (`lib/std/mem.zig`).
  - Elides `0xaa` undefined payload memset in `airWrapErrUnionErr` when `!wantSafety()` (`ReleaseFast`/`ReleaseSmall`) and in `airStore`/`airMemset` when the per-instruction AIR `safety` flag is false (`store`/`memset` vs `store_safe`/`memset_safe`), while avoiding materializing `.rodata` `0xaa` anonymous constants before `memset(.u8, ..., 0xaa)` when `safety` is enabled ([#213](https://github.com/cataggar/zig/issues/213)), elides trivially-`unreachable` branches in `airCondBr`, `lowerTry` (`catch unreachable`), and `airSwitchBr` when `!wantSafety()` ([#216](https://github.com/cataggar/zig/issues/216)), elides Wasm `block`/`br 0`/`end` wrappers for single-exit AIR `block`s (`canElideBlockWrapper`) so straight-line codegen remains uninterrupted for `Optimize.zig` and `Optimizer.zig` ([#217](https://github.com/cataggar/zig/issues/217)), and lowers all-zero `>16B` constant aggregate stores and constant null-optional / scalar-union UAV stores via immediate `v128.const 0` / `i64.const 0` / scalar stores (or `memory.fill` with `0` when `+bulk_memory_opt` is enabled) without `.rodata` UAV loads while forwarding slice coercions (`.ptr_cast` on `[]T` -> `[]const T`) and non-wrapping byref `.bit_cast`s across `SroaAnalysis`, `ExtractChecker`, and `ReadOnlyAllocAliasAnalysis` ([#218](https://github.com/cataggar/zig/issues/218), [#220](https://github.com/cataggar/zig/pull/220), [#222](https://github.com/cataggar/zig/pull/222), [#223](https://github.com/cataggar/zig/issues/223), [#224](https://github.com/cataggar/zig/pull/224)).
  - Fixes `@Vector` constant layout (`determineSimdStoreStrategy` / `abi.classifyType` alignment for 128-bit 8/16/32/64-bit lane vectors, lane-by-lane `.vector_type` constant serialization, and non-byref `.vector` extraction in `extractComptimeLeafWValue`), encodes all `std.wasm.SimdOpcode` instructions in `Emit.zig`/`Optimize.zig`, and lowers 128-bit vector arithmetic, bitwise, comparison, select, `@reduce` (pairwise `i8x16_shuffle`), and fused `cmp_vector` + `@reduce(.And/.Or)` (`v128.any_true` / `iNxM.all_true`) operations to native `v128` SIMD instructions.
- **64-Bit WebAssembly (`wasm64` / `memory64`) (`src/codegen/wasm/`, `src/link/Wasm/`)**:
  - Adds `is_64: bool` (`0x04`) to `std.wasm.Limits.Flags` and `Wasm.MemoryImport`; emits 64-bit memory limits, `i64.const` active data segment offsets, and 64-bit `memory.fill`/`memory.init` operands in `__wasm_init_memory`.
  - Fixes 64-bit fixed-width LEB128 relocations (`reloc_sleb64_table_index`, `reloc_leb64_addr`, `reloc_sleb64_addr`) in `src/link/Wasm/Flush.zig` to write 10-byte `var_i64` sequences instead of 11-byte sequences.
  - Emits `i64` stack pointer arithmetic in `src/codegen/wasm/Emit.zig` and updates pointer, slice, memory intrinsic, `call_indirect`, `@errorName`, and `@tagName` lowering in `src/codegen/wasm/CodeGen.zig` for 64-bit pointers.
- **Wasm MIR Peephole Optimizer (`src/codegen/wasm/Optimize.zig`) & Post-Link Optimizer (`src/link/Wasm/component/Optimizer.zig`)**:
  - Intrafunction multi-round pass over Wasm `Mir` before `Wasm.updateFunc`: coalesces `local.set` + `local.get` into `local.tee`, removes dead `local.tee` stores, preserves unmodified `known_locals` across structured `.block`/`.loop`/`.br_if`/`.end` scopes (`ScopeFrame`) and hoists loop-invariant `local.set` trees (`hoistLoopInvariantLocalSets`), performs intra-block store-to-load/load-to-load forwarding, narrow bit-slice extraction, `(base_local, offset, size)` non-overlap disambiguation, and overwrite dead-store elimination (`optimizeMemoryAccesses`), folds `i32`/`i64` constants/comparisons/conversions/`select`, folds non-negative constant pointer offsets into `MemArg.offset`, applies algebraic identity and strength-reduction peepholes ($2^k \pm 1$ multiply, exact 64-bit magic-multiplier `i32` division/remainder, `possibleOnesI32`/`possibleOnesI64` redundant mask stripping, `wrap(extend)` and `extend*_s(load*_u)` fusion, `eqz(xor)`/`br_if(xor)`/`select` inversion, associative constant reassociation, and duplicate pure expression `local.tee` reuse), simplifies constant branches and trivial blocks, removes unreachable instructions after unconditional transfers, rebuilds `mir_indirect_function_set` and `mir_uavs` (pruning dead anonymous constants), elides stack-pointer prologues/epilogues in frameless functions and leaf functions with stack frames (addressing frame slots directly via `$sp + offset`), and compacts sparse `mir_locals`.
  - Post-link core-module optimizer in `Flush.finish` on non-relocatable builds: parses `local.get`/`local.set`/`local.tee` as structured AST instructions, runs a 2-pass bottom-up `inlineTrivialFunctions` -> `foldDerivedPtrOffsets` -> `scalarizeShadowStackSlots` (including partial-frame per-slot SROA for non-escaping frames) -> `simplifyLocals` pipeline, `hoistLoopInvariantCode` (structured Wasm LICM for invariant multi-op expressions, proven non-aliasing loads, and single-assignment `local.set`s), `forwardAndEliminateMemoryOps` (cross-block store-to-load/load-to-load forwarding, narrow load extraction, in-place self-offset pointer folding via `foldSelfOffsetStores`, contiguous constant store coalescing up to `v128.store` via `coalesceConstantStores`, overwrite DSE, and dead shadow-stack epilogue DSE), `compactLocals` (pruning `name` section local subsections), `simplifyControlFlow` (`std.debug.assert` normalization), and `eliminateLeafStackCopy` (eliding read-only shadow-stack, caller `memory.copy`, and dead unrolled `v128`/`i64`/`i32` stack-frame copies via `matchStackFrameCopyAt` and `tryForwardDeadStackCopyInSlice`), performs mode-aware (`ReleaseSmall` vs `ReleaseFast`) multi-round inlining of trivial and parameterized leaf functions (including `0xfc`/`0xfd` stack-delta tracking, up to 4 results, 16 parameters, and 32 locals in `.fast` mode, post-early-return callees, `.small` single-caller leaf functions `<= 45` ops and 1-local accessors `<= 12` ops, and `.fast` 1- and 2-call wrapper functions and 96-op single-caller callees), prunes unreferenced `(func unreachable)` stubs and dead functions with full index remapping (including rewriting `name` custom section function and local subsections), applies core bytecode algebraic/strength-reduction peepholes ($2^k \pm 1$ `mul`, 64-bit magic `div`/`rem`, `possibleOnes` mask stripping, conversion/comparison/select fusions) while preserving post-link `i32.add`/`i64.add` wrapping semantics, and preserves custom sections and SIMD (`0xfd`) / atomic (`0xfe`) / WasmFX continuation instructions ([#223](https://github.com/cataggar/zig/issues/223), [#224](https://github.com/cataggar/zig/pull/224)).
- **WASI Component Model Pipeline (`src/link/Wasm/component/`, `src/link/Wasm/Flush.zig`, `src/link/Lld.zig`)**:
  - In-memory WIT lexer/parser/resolver and metadata encoder with embedded canonical WASI 0.2.6, 0.2.12, and 0.3.0 WIT definitions (`src/link/Wasm/component/wit/`).
  - Synthesizes zero-adapter WASI 0.2.6 and 0.3.0 components with `world_gc` import pruning, supports custom WIT worlds (`-fwit-path`, `-fwit-world`), and automatically splices `wasi_snapshot_preview1` command/reactor adapters when Preview 1 imports are present or `-fwasi-adapter` is specified.
  - Supports 64-bit Component Model (`cm64`) ABI lowering (`lowerCoreSigForArch` with `is_memory64`, flattening `(ptr, len)`, spilled parameter pointers, `retptr`, and WASI 0.3 async/stream/future/waitable/error-context canonical builtins to `i64`).
  - Wraps both self-hosted Wasm linker output (`src/link/Wasm/Flush.zig`) and `wasm-ld` output (`src/link/Lld.zig`) into valid WASI components.

### Affected Files
- `lib/std/wasm.zig`, `lib/std/Target/wasm.zig`
- `src/codegen/wasm/CodeGen.zig`, `src/codegen/wasm/Emit.zig`, `src/codegen/wasm/Mir.zig`, `src/codegen/wasm/Optimize.zig`, `src/codegen/wasm/abi.zig`, `src/codegen/wasm/assembly.zig`
- `src/link/Wasm.zig`, `src/link/Wasm/Archive.zig`, `src/link/Wasm/Flush.zig`, `src/link/Wasm/Object.zig`
- `src/link/Wasm/component/**`
- `src/link/Lld.zig`
- `test/behavior/bit_shifting.zig`, `test/behavior/math.zig`, `test/behavior/maximum_minimum.zig`, `test/behavior/optional.zig`, `test/behavior/switch.zig`, `test/behavior/vector.zig`, `test/behavior/wasm.zig`

---

## 4. C Standard Library in Zig (`lib/c` / `libzigc`)

Migrates C standard library translation units from bundled musl C and `wasi-libc` C into native Zig under `lib/c/`, enabling `-lc` on WASI targets to build 100% from Zig without Clang or LLVM.

### Commits
- [`e72abbbe67`](https://github.com/cataggar/zig/commit/e72abbbe67cec22b859b235a62ea4f8dbea29cda) — `lib/c: port libc17-704 libzigc onto 0.17.0` ([#69](https://github.com/cataggar/zig/pull/69))
- [`c3528f430c`](https://github.com/cataggar/zig/commit/c3528f430ca0b3f77e5ae8a9e61adfc78096a679) — `lib/c: wire unistd, ldso, mman, conf, issetugid, time32, and complex parity` ([#72](https://github.com/cataggar/zig/pull/72))
- [`e238f784d6`](https://github.com/cataggar/zig/commit/e238f784d604ab8fcef849a41c0a99edb8292ff3) — `libc: migrate variadic stdio and syscall wrappers to Zig` ([#74](https://github.com/cataggar/zig/pull/74))
- [`667417996e`](https://github.com/cataggar/zig/commit/667417996e9a297e0ae363457656671cbf10e7a5) — `libzigc: migrate remaining math, regex, and locale units from musl` ([#77](https://github.com/cataggar/zig/pull/77))
- [`8b547cb570`](https://github.com/cataggar/zig/commit/8b547cb57089d472e7f49a3bd1480da95234059a) — `libzigc: migrate iconv.c and strfmon.c to lib/c/locale.zig` ([#78](https://github.com/cataggar/zig/pull/78))
- [`333accf5cd`](https://github.com/cataggar/zig/commit/333accf5cdce313efddcdad14d512125e5c8b063) — `lib/c: fix 0.17.0-libc validation issues across musl and wasi` ([#79](https://github.com/cataggar/zig/pull/79))
- [`caed8ffeb2`](https://github.com/cataggar/zig/commit/caed8ffeb263ca1226ef9448fc189651b0c34df6) — `wasi-libc: migrate all remaining 337 C sources and CRT to libzigc` ([#88](https://github.com/cataggar/zig/issues/88), [#89](https://github.com/cataggar/zig/pull/89))
- [`7a50004235`](https://github.com/cataggar/zig/commit/7a50004235221b49caee9c96cc61fc75e668bfd8) — `lib/c: fix WASI currentLocaleSlot in iconv and avoid TLS in wasi_sources` ([#89](https://github.com/cataggar/zig/pull/89))
- [`ca181af18a`](https://github.com/cataggar/zig/commit/ca181af18aa7a2ebb74061890480f19343b83452) — `wasi, libc: cache lib/c as libzigc.a and fix reactor exports` ([#130](https://github.com/cataggar/zig/issues/130), [#136](https://github.com/cataggar/zig/pull/136))
- [`63bc0870ec`](https://github.com/cataggar/zig/commit/63bc0870ec555a7369a659b992160399a780af9b) — `wasi, libc: share wasip3 descriptor table and BrkAllocator state across ZCUs` ([#130](https://github.com/cataggar/zig/issues/130), [#152](https://github.com/cataggar/zig/pull/152))

### Key Changes
- **Linux/musl C-to-Zig Migration (`lib/c/*.zig`, `src/libs/musl.zig`)**:
  - Ports 681 musl `.c` units (1,646+ exported symbols) to `lib/c/`: `stdio` (including variadic `vfprintf`/`vfscanf`/`vsnprintf`/`vswprintf` family), `math` (all `f32`/`f64`/`f80`/`f128` routines with IEEE-754 exception parity), `locale` (including full `iconv` character tables and `strfmon`), `regex` (`fnmatch`, `glob`, `regcomp`, `regexec`), `thread`, `time`, `process`, `signal` (including `KernelSigaction` padding for RISC-V), `unistd`, `ldso`, `sys/mman`, `conf`, `env`, `fenv`, `setjmp`, `search`, `crypt`, `ctype`, `multibyte`, `network`, `passwd`, `spawn`, `stat`, `stdlib`, `string`, `aio`, `complex`, `dirent`, `errno`, `exit`, `fcntl`, `fts`, `ipc`, `legacy`, `linux`, `misc`, `mq`, `sched`, `sys/select`, `temp`, and `termios`.
- **Pure-Zig WASI `libc` (`lib/c/wasi_*.zig`, `src/libs/wasi_libc.zig`, `src/Compilation.zig`, `src/link/Lld.zig`)**:
  - Migrates all 337 `wasi-libc` C source files and CRT startup files (`wasi_crt1_command.zig`, `wasi_crt1_reactor.zig`, `wasi_cloudlibc.zig`, `wasi_sources.zig`, `wasi_thread_stub.zig`) to `buildOutputFromZig`, eliminating C compilation when building `-lc` for `wasm32-wasi`, `wasm32-wasip2`, `wasm32-wasip3`, and `wasm64-wasip3`.
  - Caches `lib/c` as `libzigc.a` (`zigc_strat = .lib`) on WASI instead of compiling 2,157 `@export`s into every user ZCU, shares `std.os.wasi.p3.State` (`__zig_wasip3_state`) and `std.heap.BrkAllocator.State` (`__zig_wasm_brk_allocator`) across `libzigc.a`, `crt1-*.o`, and the user ZCU when linking libc, places `libzigc.a` after user and C++ objects in `Lld.wasmLink`, declares `__main_argc_argv` with weak linkage in `mainVoidImpl`, and hides internal globals (`__progname*`, `optarg`) on WebAssembly so `-rdynamic` reactor builds do not fail or leak libc globals.
- **Win32 `lib/c` Modules (`lib/c/win32/*.zig`, `src/libs/mingw.zig`)**:
  - Implements Win32 `time`, `signal`, `process`, `misc`, and POSIX compatibility stubs under `lib/c/win32/`.

### Affected Files
- `lib/c.zig`, `lib/c/**`
- `src/Compilation.zig`, `src/link/Lld.zig`
- `src/libs/musl.zig`, `src/libs/wasi_libc.zig`, `src/libs/mingw.zig`
- `test/c.zig`, `test/libc.zig`, `test/src/Libc.zig`

---

## 5. LLVM Backend, `zig cc` Linker Flags, and Static LLVM on WASI (`wazigl`)

Fixes multi-architecture `VaList`/`@cVaArg` ABI lowering, cross-module inline debug info stripping, `zig cc` linker script and common-symbol flags, and static LLVM/Clang/LLD compilation targeting `wasm64-wasip3`.

### Commits
- [`6af9ad0cc0`](https://github.com/cataggar/zig/commit/6af9ad0cc0df66200ae5e8f5590f1c111da6aa42) — `compiler: port VaList and @cVaArg fixes for x86_64, aarch64, and s390x` ([#70](https://github.com/cataggar/zig/pull/70))
- [`6c3c018259`](https://github.com/cataggar/zig/commit/6c3c0182592100ae04ed0d9af37e3359f2ea078e) — `Sema: propagate strip across inline call chain` ([#62](https://github.com/cataggar/zig/issues/62), [#94](https://github.com/cataggar/zig/pull/94))
- [`c5a7f27af6`](https://github.com/cataggar/zig/commit/c5a7f27af69cadab6ab474953640cd02af4326a7) — `zig cc: support define-common, default scripts, and ordered linker scripts` ([#60](https://github.com/cataggar/zig/issues/60), [#105](https://github.com/cataggar/zig/pull/105))
- [`20f22e1f0a`](https://github.com/cataggar/zig/commit/20f22e1f0a57f05ac226d60e562ead9ad46ba3ee) — `wasi: support wasm64-wasip3 C/C++, static LLVM, and wazig/wazigl releases` ([#117](https://github.com/cataggar/zig/pull/117))
- [`113621a0c9`](https://github.com/cataggar/zig/commit/113621a0c92a981741a3bc5ac1a28eb95a210354) — `Enable wasm64-wasip3 static LLVM linking for wazigl release` ([#118](https://github.com/cataggar/zig/pull/118))
- [`37ab69369b`](https://github.com/cataggar/zig/commit/37ab69369b6e166aa2ff536418b84a2127939c1b) — `wasi: guard empty metadataString in LLVM debug info and undraft re-tagged releases` ([#124](https://github.com/cataggar/zig/pull/124))
- [`25bcd82e14`](https://github.com/cataggar/zig/commit/25bcd82e14b51af5f9fe0f533530174b77f1fd0a) — `wasm: export __stack_pointer by default for -rdynamic, reactor, and WASI P3 builds` ([#160](https://github.com/cataggar/zig/issues/160), [#167](https://github.com/cataggar/zig/pull/167))

### Key Changes
- **`VaList` & `@cVaArg` Lowering (`src/codegen/llvm/FuncGen.zig`, `src/Sema.zig`)**:
  - `x86_64` SysV: classifies `std.builtin.VaList` parameters as `.byref_mut` (invisible reference) instead of `.memory` + `byval`.
  - `x86_64` Windows/UEFI: enables `VaList` (`*u8`) and lowers `@cVaArg` with 8-byte slot advances and indirect `>8B` loads.
  - `aarch64`/`aarch64_be` AAPCS64: enables `VaList` and lowers `@cVaArg` manually for scalars, composites, HFAs, and `>16B` indirect arguments.
  - `s390x` ELF: lowers `@cVaArg` manually to avoid LLVM SystemZ `ISD::VAARG` selection aborts.
  - Fallback `@cVaArg`: handles `.in_memory` `TypeRepr` values via `alloca` store.
- **Cross-Module Inlining & LLVM Debug Info (`src/Sema.zig`, `src/codegen/llvm.zig`, `src/codegen/llvm/FuncGen.zig`)**:
  - Adds `Block.strip()` in `src/Sema.zig` to walk the inline call chain so inlining across stripped and unstripped modules does not emit orphan debug instructions or dangling DWARF references.
  - Guards empty path or variable name slices in `llvm.getDebugFile` and `FuncGen.airDbgVarPtr` by passing `null` instead of calling `Builder.metadataString("")` (which asserts `bytes.len > 0` when `dirs.cwd` is `""` on WASI).
- **`zig cc` Linker Flags (`src/main.zig`, `src/link.zig`, `src/link/Elf.zig`, `src/link/Elf/relocatable.zig`, `src/link/Lld.zig`)**:
  - Supports `-d`, `-dc`, `-dp`, `--define-common`, and `--no-define-common` (converting `SHN_COMMON` symbols into `.bss` allocations during `-r` relocatable links in both LLD post-link fixup and the self-hosted ELF linker).
  - Supports `-dT` / `--default-script` and preserves multiple `-T` / `--script` flags in command-line order across top-level CLI and `-Wl,` arguments.
- **Static LLVM/Clang/LLD on `wasm64-wasip3` (`build.zig`, `src/zig_llvm.cpp`, `src/libs/libcxx.zig`, `lib/libc/include/wasm-wasi-musl/`)**:
  - Fixes `wasm64` `INT64_C`/`UINT64_C` vs `INTPTR_MAX`/`SIZE_MAX` definitions in `lib/libc/include/wasm-wasi-musl/bits/{stdint,posix}.h` and `wasi/api.h`.
  - Enables `libcxx` threads and filesystem support on WASI (`src/libs/libcxx.zig`, `lib/libcxx/src/filesystem/operations.cpp`), disables `-fPIC` default on Wasm targets, and provides WASI stubs for `getauxval` and `__cxa_thread_atexit` in `src/zig_llvm.cpp`.
  - Passes `--export-if-defined=__stack_pointer` to `wasm-ld` in `Lld.wasmLink` when `shouldExportStackPointerForConfig` is enabled (`-rdynamic`, `-mexec-model=reactor`, dynamic WASI library, or `wasip3`) and `--export=__stack_pointer` is not already specified.

### Affected Files
- `src/Sema.zig`, `src/codegen/llvm.zig`, `src/codegen/llvm/FuncGen.zig`, `lib/std/zig/llvm/Builder.zig`
- `src/main.zig`, `src/link.zig`, `src/link/Elf.zig`, `src/link/Elf/Object.zig`, `src/link/Elf/Symbol.zig`, `src/link/Elf/relocatable.zig`, `src/link/Lld.zig`
- `build.zig`, `src/zig_llvm.cpp`, `src/libs/libcxx.zig`
- `lib/libc/include/generic-musl/stdint.h`, `lib/libc/include/wasm-wasi-musl/bits/posix.h`, `lib/libc/include/wasm-wasi-musl/bits/stdint.h`, `lib/libc/include/wasm-wasi-musl/wasi/api.h`, `lib/libcxx/src/filesystem/operations.cpp`

---

## 6. Self-Hosted `x86_64` and `aarch64` Backends

Fixes register allocation and instruction selection bugs in the self-hosted `x86_64` and `aarch64` backends, enabling `stage2_aarch64` to self-host the full Zig compiler without LLVM.

### Commits
- [`29fa659ca2`](https://github.com/cataggar/zig/commit/29fa659ca221a3e9127fe7ab4e8470f420a8b543) — `aarch64, wasip3: fix self-hosted backend for compiler_rt/Maker and wasip3 exit codes` ([#92](https://github.com/cataggar/zig/issues/92), [#93](https://github.com/cataggar/zig/pull/93))
- [`6999ac3e6f`](https://github.com/cataggar/zig/commit/6999ac3e6ff8658ab84dbce5c934301c6bca7b4a) — `stage2_aarch64: fix Select.zig cases to self-host full compiler` ([#96](https://github.com/cataggar/zig/issues/96), [#103](https://github.com/cataggar/zig/pull/103))
- [`ee9797f5e0`](https://github.com/cataggar/zig/commit/ee9797f5e0988184a578a3beb05255c2b6362c29) — `x86_64: fix register-spill restore clobbering branch results` ([#61](https://github.com/cataggar/zig/issues/61), [#104](https://github.com/cataggar/zig/pull/104))
- [`490dd6253e`](https://github.com/cataggar/zig/commit/490dd6253e825ce8b313dca21102957eacff0349) — `aarch64: fuse MADD/MSUB/CBZ/CMN/UBFX, zero stores, and leaf prologues` ([#201](https://github.com/cataggar/zig/issues/201), [#210](https://github.com/cataggar/zig/pull/210))
- [`cee6fef2e3`](https://github.com/cataggar/zig/commit/cee6fef2e306f29795a2b3f9bfd3234e4a0265ae) — `x86_64: zero-extend tracking, 3-component LEA/SIB folding, and EFLAGS-preserving zero moves` ([#202](https://github.com/cataggar/zig/issues/202), [#211](https://github.com/cataggar/zig/pull/211))
- [`04c4fa26fc`](https://github.com/cataggar/zig/commit/04c4fa26fceea01dc00945976418205c00d41ead) — `aarch64: mark .lr saved in helper calls, panics, and explicit asm bindings` ([#219](https://github.com/cataggar/zig/issues/219), [#221](https://github.com/cataggar/zig/pull/221))

### Key Changes
- **Self-Hosted `x86_64` (`src/codegen/x86_64/CodeGen.zig`)**:
  - Acquires destination registers with `getValue` *after* `genCopy` (or after `materializeUnsafe` and `freeValue` in `reuseOperandAdvanced`) in `airBr` and `airSwitchDispatch`, preventing a register-spill restore during `genCopy` from overwriting a newly written two-register branch result.
  - Uses `freeValue` in `airSwitchDispatch` so `register_pair` operands are completely freed.
  - Elides redundant `mov r32, r32` in `.int_cast` when widening unsigned 32-bit GPR values guaranteed to be zero-extended by 32-bit x86_64 instructions (`isGuaranteedZeroExtended32`), folds 3-component `base + (index << scale) + disp` into a single `lea` / SIB `.register_offset` addressing mode across `.ptr_add` and `.add`/`.add_wrap`, and preserves `EFLAGS` across zero register moves (`mov r32, 0` when `eflags_inst != null`) and non-flag-clobbering `Select.select` conversions ([#202](https://github.com/cataggar/zig/issues/202)).
- **Self-Hosted `aarch64` (`src/codegen/aarch64/Select.zig`, `src/codegen/aarch64.zig`, `src/codegen/aarch64/instructions.zon`, `src/codegen.zig`)**:
  - Implements missing and incomplete AIR instruction selection cases required to self-host the Zig compiler, `compiler_rt`, `Maker`, and `configurer` on `aarch64-linux` with `-Duse-llvm=false`.
  - Fixes branch merge and `liveIn` register liveness when a parent aggregate and its sub-part are simultaneously live across basic block boundaries (`splitAncestorRegs`, `spillReg`, `defLiveIn`, `merge`).
  - Skips storing union tags in `.set_union_tag` when `union_layout.tag_size == 0`, and types `parts_len` as `Value.PartsLen` for 32-bit host/target compatibility.
  - Fuses single-use in-block `.mul`/`.mul_wrap` into `MADD`/`MSUB`/`MNEG`, `.not` into `BIC`/`ORN`/`EON`, `(x >> lsb) & mask` into `UBFX` (`ubfm`), shifted-register ALU operands and `#imm12, lsl #12` immediates into `.add`/`.sub`/bitwise ops, compare-with-zero `.cond_br` into `CBZ`/`CBNZ`, negative 12-bit immediate comparisons into `CMN`, constant zero stores into `STR WZR/XZR`, stripped leaf function prologues/epilogues without `fp`/`lr` frame records (recording `.lr` in `saved_registers` across runtime helper calls, panics, and explicit inline-asm bindings so non-leaf functions preserve `lr`), and rotating spill eviction candidates across `r0..r15` ([#201](https://github.com/cataggar/zig/issues/201), [#219](https://github.com/cataggar/zig/issues/219)).

### Affected Files
- `src/codegen/x86_64/CodeGen.zig`
- `src/codegen/aarch64.zig`, `src/codegen/aarch64/Select.zig`, `src/codegen/aarch64/instructions.zon`, `src/codegen.zig`
- `test/behavior/if.zig`, `test/behavior/switch_loop.zig`, `test/behavior/bugs/96_aarch64_selfhost.zig`

---

## 7. Standard Library Networking & HTTP Fixes (`std.http.Client`, `ResolvConf`)

Fixes HTTPS over HTTP `CONNECT` proxy tunnels and `/etc/resolv.conf` parsing for large corporate/WSL `search` lists.

### Commits
- [`d6b022846c`](https://github.com/cataggar/zig/commit/d6b022846c83ddb75987e1e2b1379ac3bb997297) — `std.http.Client: upgrade CONNECT proxy tunnels to TLS for https targets` ([#56](https://github.com/cataggar/zig/issues/56), [#106](https://github.com/cataggar/zig/pull/106))
- [`348f24280a`](https://github.com/cataggar/zig/commit/348f24280aadb6e02d870176c629aad357ee96cb) — `std.Io.net.HostName.ResolvConf: expand search/line buffers to 4 KiB and harden parsing` ([#59](https://github.com/cataggar/zig/issues/59), [#107](https://github.com/cataggar/zig/pull/107))

### Key Changes
- **HTTPS Proxy `CONNECT` TLS Upgrade (`lib/std/http/Client.zig`)**:
  - Passes the target `protocol` into `connectProxied` so connection-pool lookups match on `.protocol = protocol` instead of `proxy.protocol`, and `connectTcpOptions` only queries the pool when `options.proxied_host == null`.
  - Upgrades established `200 OK` `CONNECT` tunnel streams to TLS via `Connection.Tls.create` when `protocol == .tls`, replacing the `Connection.Plain` pool entry and returning `error.TlsInitializationFailed` directly on handshake failure rather than falling back to cleartext proxy forwarding.
- **DNS `ResolvConf` Parsing (`lib/std/Io/net/HostName.zig`, `lib/std/Io/Threaded.zig`)**:
  - Expands `ResolvConf.search_buffer` (`max_search_len = 4096`) and `line_buf` from 254/512 bytes to 4096 bytes.
  - Copies validated whole domain suffixes up to `max_search_len` (truncating on domain boundaries) and drains overlong lines (`error.StreamTooLong`) to `\n` instead of failing DNS resolution with `error.ResolvConfParseFailed`.
  - Accepts final lines without a trailing newline, strips both `#` and `;` comments, handles `\r`, ignores malformed `nameserver` entries, clamps `attempts` (`1..10`) and `timeout_seconds` (`1..60`), and bounds `canon_name + "." + token` in `Threaded.lookupDnsSearch`.

### Affected Files
- `lib/std/http/Client.zig`, `lib/std/http/test.zig`
- `lib/std/Io/net/HostName.zig`, `lib/std/Io/Threaded.zig`
