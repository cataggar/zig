![ZIG](https://ziglang.org/img/zig-logo-dynamic.svg)

A general-purpose programming language and toolchain for maintaining
**robust**, **optimal**, and **reusable** software.

https://ziglang.org/

## `cataggar/zig` Fork & Mirror

A personal mirror and build of the [Zig](https://ziglang.org) compiler.

### Branches

- **`wazig`** (default) — WebAssembly (`wasm64-wasip3`) Zig compiler (`wazig` and
  `wazigl`) source tree, plus the release and CI workflows that mirror official
  Zig releases and build development binaries.
- **`master`** — a mirror of the upstream Zig source from
  [codeberg.org/ziglang/zig](https://codeberg.org/ziglang/zig) (the Zig project
  migrated from GitHub to Codeberg). Synced daily at 5:15 AM Central Time
  (`America/Chicago`), automatically adjusting for daylight saving time.

### Releases

Only stable Zig releases are mirrored automatically. Development releases
require a manual workflow run.

Releases here include official mirrored binaries, signed development builds, and
unsigned WebAssembly (`wasm64-wasip3`) builds (`wazig` and `wazigl`). Native
releases are signed with different [minisign](https://jedisct1.github.io/minisign/)
public keys; install them with [`ghr`](https://github.com/cataggar/ghr), passing
the matching public key so the download is signature-verified.

#### Official Zig binaries (mirrored from ziglang.org)

Mirrored unchanged from <https://ziglang.org/download/> and verified with the
official Zig minisign key:

```sh
MINISIGN_PUB=RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U
ghr install cataggar/zig@v0.16.0 $MINISIGN_PUB
ghr install cataggar/zig@v0.17.0 $MINISIGN_PUB
```

#### Development binaries

My own builds (for example the libzigc musl-libc-in-Zig work, issue #17),
published manually and signed with my own key. The `build-release` workflow
uses stable Zig 0.17.0 as its host compiler:

```sh
MINISIGN_PUB=RWQhfv+qEYWFiUiUqTeTGnyN3KQlTSVNpqhCST5HbBKZRi6SfCJhnVF4
```

#### WebAssembly (`wasm64-wasip3`) Releases (`wazig` and `wazigl`)

Pre-built WebAssembly (`wasm64-wasip3`) compiler releases are published in two flavors:

* **`wazig`**: Zig compiler with self-hosted backends (without LLVM).
* **`wazigl`**: Zig compiler with LLVM, Clang, and LLD statically linked in.

Each release publishes an unsigned `<flavor>.tar.zst` archive (containing `<flavor>.wasm` and a Wasm-focused `lib/` directory) and a `<flavor>.tar.zst.ghr` manifest sidecar (no `.minisig` files). Install using [`ghr`](https://github.com/cataggar/ghr) v0.10.2+:

```sh
ghr install cataggar/zig@v0.17.0-wazig.2
# or with LLVM included:
ghr install cataggar/zig@v0.17.0-wazigl.2
```

To run manually with Wasmtime after extracting `<flavor>.tar.zst`, mount `<extracted-dir>/lib` at guest `/lib` (pass `--zig-lib-dir` or set `ZIG_LIB_DIR` when cross-compiling against native target headers):

```sh
zstd -dc wazig.tar.zst | tar -C /path/to/wazig -xf -
wasmtime run \
  -W component-model-memory64=y \
  -W component-model-async=y \
  -W component-model-async-stackful=y \
  -W component-model-more-async-builtins=y \
  -W component-model-error-context=y \
  -W max-wasm-stack=67108864 \
  -W async-stack-size=67108864 \
  -S p3=y \
  -S cli-exit-with-code=y \
  -S inherit-env=y \
  --dir=/path/to/wazig/lib::/lib \
  --dir=. \
  /path/to/wazig/wazig.wasm build-exe hello.zig -target wasm32-wasi -fno-llvm
```

## Documentation

* [`doc/wazig-changes.md`](doc/wazig-changes.md) — Summary of all compiler, linker, standard library, and `lib/c` changes in `wazig` since Zig 0.17.0.
* [`doc/building.md`](doc/building.md) — Building `wazig`/`wazigl`, Zig, and LLVM/Clang/LLD from source across POSIX and Windows.
* [`doc/debugging-and-testing.md`](doc/debugging-and-testing.md) — Editing source code, running the test suite (native, QEMU, Wine, Wasmtime), Autodoc, `translate-c`, and debugging with LLDB.
* [`doc/libc-release-notes.md`](doc/libc-release-notes.md) — `libzigc` release notes.
* [`doc/build.zig.zon.md`](doc/build.zig.zon.md) — `build.zig.zon` package manifest specification.

For official Zig documentation, refer to the **Release Notes**, **Language
Reference**, or **Standard Library Documentation** on the
[Zig download page](https://ziglang.org/download), or run `zig std` from a
release installation.

