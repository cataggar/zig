# Copilot Instructions for Zig Compiler

## NEVER create upstream pull requests

The Zig project explicitly bans AI-generated contributions (code, issues, PRs, and comments).
See: https://ziglang.org/news/migrating-from-github-to-codeberg/
See: https://codeberg.org/Codeberg/Community/issues/2458

**Do NOT:**
- Create pull requests targeting codeberg.org/ziglang/zig
- Create issues on codeberg.org/ziglang/zig
- Post comments on codeberg.org/ziglang/zig

All work must stay in the cataggar or ctaggart forks on GitHub. Any upstream
contributions must be manually submitted by a human after thorough review.

## GitHub account usage

The `ctaggart/zig` repo is owned by a different GitHub account. To perform
admin operations (e.g. changing default branch, dispatching workflows), switch
accounts:

```powershell
gh auth switch --user ctaggart   # for ctaggart-owned repos
gh auth switch --user cataggar   # to switch back
```

## `wazig`, `wazigl`, and `zigc` release descriptions

When creating or updating `wazig*` (`v*-wazig.*` and `v*-wazigl.*`) or `zigc` (`v*-zigc.*`) GitHub release descriptions in `cataggar/zig`:

- Always include a `### Highlights` section summarizing the key changes in that release, using unquoted `#<number>` (or `owner/repo#<number>`) references so GitHub auto-links them.
- `wazigl` (`v*-wazigl.*`) release descriptions must link to the matching `wazig` release (e.g., `Includes everything in [v0.17.0-wazig.N](https://github.com/cataggar/zig/releases/tag/v0.17.0-wazig.N), plus LLVM-specific ...:`) and list **only** LLVM/Clang/LLD-specific highlights under `### Highlights`. Do not duplicate general `wazig` items in `wazigl` release descriptions.
- `wazig` and `wazigl` publish unsigned `<flavor>.tar.zst` (containing `<flavor>.wasm` and `lib/` at archive root) and `<flavor>.tar.zst.ghr` assets, with no `.minisig` files.
- `zigc` (`v*-zigc.*`) publishes unsigned `zigc-x86_64-linux-<version>.tar.zst` and `zigc-aarch64-linux-<version>.tar.zst` native Linux archives (built without LLVM using Zig's self-hosted native backends, containing `zigc`, full `lib/`, `LICENSE`, and `README.md`), with no `.minisig` files, installed via `ghr install cataggar/zig@<tag> "?id=cataggar/zig/zigc"`.

## Building

### With LLVM (full build — produces `stage3/bin/zig`)

Using a prior Zig + LLVM dev kit (`$DEVKIT`):

```
$DEVKIT/bin/zig build -p stage3 --search-prefix $DEVKIT --zig-lib-dir lib -Dstatic-llvm
```

Append `-Doptimize=ReleaseSafe` for a release build. On Windows with the dev kit, add `-Duse-zig-libcxx -Dtarget=x86_64-windows-gnu`.

Alternatively, via CMake + Ninja:

```
mkdir build && cd build
cmake .. -GNinja -DCMAKE_PREFIX_PATH="$DEVKIT" -DZIG_STATIC=ON
ninja install
```

### Without LLVM (bootstrap — produces `zig2`)

Only requires a C compiler:

```
cc -o bootstrap bootstrap.c
./bootstrap
```

This builds a stage2 compiler without LLVM extensions (no release optimizations, no C/C++ compilation, limited linking).

## Testing

Run the full test suite:

```
zig build test --zig-lib-dir lib
```

Key build options for narrowing tests:

- `-Dskip-non-native` — only native target tests
- `-Dskip-release` — skip release mode builds
- `-Dskip-debug` — skip debug builds
- `-Dskip-compile-errors` — skip compile error tests
- `-Dskip-llvm` — skip LLVM backend tests

Run a single behavior test file directly:

```
zig test --zig-lib-dir lib test/behavior.zig
```

Run a specific standalone test case:

```
zig build test -Dskip-non-native -Dno-matrix
```

Build and check documentation:

```
zig build docs --zig-lib-dir lib
```

## Architecture

### Compilation Pipeline

Source code flows through these stages:

1. **Lex/Parse** (`lib/std/zig/Ast.zig`) — Zig source → AST. The lexer and parser live in the standard library, not in `src/`.
2. **AstGen** (`lib/std/zig/AstGen.zig`) — AST → ZIR (Zig Intermediate Representation). Also in the standard library.
3. **Sema** (`src/Sema.zig`) — ZIR → AIR (Analyzed Intermediate Representation). This is the heart of the compiler: type checking, comptime evaluation, safety-check generation.
4. **Codegen** (`src/codegen.zig`, `src/codegen/`) — AIR → machine code or other output formats. Multiple backends: LLVM (`codegen/llvm.zig`), C (`codegen/c.zig`), and native backends for aarch64, x86_64, ARM, RISC-V, WASM, SPARC, MIPS, SPIR-V.
5. **Linking** (`src/link.zig`, `src/link/`) — Produces final executables/libraries. Includes ELF, MachO, COFF/PE, WASM, and SPIR-V linkers plus an LLD integration (`link/Lld.zig`).

### Key Components

- **`src/Compilation.zig`** — Top-level orchestrator. Manages the overall compilation process; a `Compilation` may or may not have Zig source code.
- **`src/Zcu.zig`** — Zig Compilation Unit. Represents compilation of Zig source code specifically. Each `Compilation` has zero or one `Zcu`.
- **`src/InternPool.zig`** — Self-contained data structure for interned objects (types, values). Thread-safe with sharded design. Central to how the compiler represents types and values.
- **`src/Type.zig`** / **`src/Value.zig`** — Type and value representations, backed by the InternPool.
- **`src/Air.zig`** — Analyzed Intermediate Representation — the typed IR that backends consume.
- **`src/Package.zig`** — Package/module resolution.
- **`src/main.zig`** — CLI entry point, dispatches to subcommands (`build-exe`, `build-obj`, `test`, `run`, `cc`, `c++`, etc.).

### Bootstrap Stages

- **stage1** (`stage1/`) — Contains `zig1.wasm`, a WebAssembly build of the compiler used for bootstrapping. `bootstrap.c` is a WASM interpreter that runs `zig1.wasm` to produce a stage2 binary.
- **stage2** — The compiler built by stage1 (the `zig2` binary from bootstrapping).
- **stage3** (`stage3/`) — The compiler built by stage2 (or by a prior Zig + LLVM). This is the final product: `stage3/bin/zig`.

### `dev.zig` Feature Gating

`src/dev.zig` defines a feature-gating system (`Env` enum) that controls which compiler features are available at different build stages: `bootstrap`, `core`, `full`, and target-specific environments. This allows incremental development of backends.

### Directory Layout

- **`lib/`** — Ships with the Zig installation. Contains the standard library (`lib/std/`), compiler runtime (`lib/compiler_rt.zig`), bundled libc headers, libcxx, and the frontend (lexer, parser, AstGen are in `lib/std/zig/`).
- **`src/`** — The compiler itself (Sema, codegen, linking, CLI).
- **`test/`** — Test suites: `behavior/` (runtime behavior tests), `cases/` (compile error/codegen cases), `standalone/` (end-to-end tests), `cli/` (CLI tests), `incremental/` (incremental compilation tests).
- **`tools/`** — Maintenance scripts for updating bundled headers, CPU features, syscall tables, etc.

## Conventions

### File As-Struct Pattern

Zig files that represent a single type use `const Self = @This();` at the top. Files are named in PascalCase when they represent a type (e.g., `Compilation.zig`, `InternPool.zig`, `Sema.zig`), and snake_case for modules/namespaces (e.g., `codegen.zig`, `target.zig`).

### Scoped Logging

Each module declares its own scoped logger:

```zig
const log = std.log.scoped(.compilation);
```

### Error Handling

The compiler uses error unions extensively. `CompileError` from `Zcu.zig` is the standard error type for compilation failures. Functions that can fail during codegen return `CodeGenError`.

### Tracy Integration

Performance tracing is available via `src/tracy.zig`. Functions use `const t = trace(@src()); defer t.end();` for instrumentation. Enable with `-Dtracy=<path-to-tracy-source>`.

### InternPool Threading Model

The `InternPool` uses a sharded design for thread safety. Operations are indexed by thread ID (`tid`). The number of shards is a power of two matching the number of simultaneous writer threads.
