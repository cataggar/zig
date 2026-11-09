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

Releases are installed with [`ghr`](https://github.com/cataggar/ghr). See
[`doc/installation.md`](doc/installation.md) for minisign signature verification
and running `wazig.wasm` / `wazigl.wasm` directly with `wasmtime`.

#### Official Zig Releases (mirrored from ziglang.org)

Stable Zig releases are mirrored automatically from
<https://ziglang.org/download/>:

```sh
ghr install cataggar/zig@v0.17.0
```

#### WebAssembly (`wasm64-wasip3`) Releases (`wazig` and `wazigl`)

Pre-built WebAssembly (`wasm64-wasip3`) compiler releases are published in two
flavors:

* **`wazig`**: Zig compiler with self-hosted backends (without LLVM):

```sh
ghr install cataggar/zig@v0.17.0-wazig.6
```

* **`wazigl`**: Zig compiler with LLVM, Clang, and LLD statically linked in:

```sh
ghr install cataggar/zig@v0.17.0-wazigl.6
```

Run `wazig`:

```sh
wazig version
wazig --help
```

## Documentation

* [`doc/installation.md`](doc/installation.md) — Installing `wazig`, `wazigl`, and native Zig releases with `ghr`, minisign verification keys, and running directly with `wasmtime`.
* [`doc/wazig-changes.md`](doc/wazig-changes.md) — Summary of all compiler, linker, standard library, and `lib/c` changes in `wazig` since Zig 0.17.0.
* [`doc/building.md`](doc/building.md) — Building `wazig`/`wazigl`, Zig, and LLVM/Clang/LLD from source across POSIX and Windows.
* [`doc/debugging-and-testing.md`](doc/debugging-and-testing.md) — Editing source code, running the test suite (native, QEMU, Wine, Wasmtime), Autodoc, `translate-c`, and debugging with LLDB.
* [`doc/build.zig.zon.md`](doc/build.zig.zon.md) — `build.zig.zon` package manifest specification.

For official Zig documentation, refer to the **Release Notes**, **Language
Reference**, or **Standard Library Documentation** on the
[Zig download page](https://ziglang.org/download), or run `zig std` from a
release installation.

