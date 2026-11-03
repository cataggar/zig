# Installing `wazig`, `wazigl`, and Zig Releases

Releases in `cataggar/zig` can be installed using [`ghr`](https://github.com/cataggar/ghr).

---

## WebAssembly (`wasm64-wasip3`) Releases (`wazig` and `wazigl`)

Pre-built WebAssembly (`wasm64-wasip3`) compiler releases are published in two flavors:

* **`wazig`**: Zig compiler with self-hosted backends (without LLVM).
* **`wazigl`**: Zig compiler with LLVM, Clang, and LLD statically linked in.

Each release publishes an unsigned `<flavor>.tar.zst` archive (containing `<flavor>.wasm` and a Wasm-focused `lib/` directory at archive root) and a `<flavor>.tar.zst.ghr` manifest sidecar (no `.minisig` files).

### Installing with `ghr`

Install `wazig` using `ghr` v0.10.2+:

```sh
ghr install cataggar/zig@v0.17.0-wazig.2
```

Or install `wazigl` (with LLVM included):

```sh
ghr install cataggar/zig@v0.17.0-wazigl.2
```

Verify the installed CLI shim:

```sh
wazig version
wazig --help
```

### Running Directly with `wasmtime`

To run `wazig.wasm` or `wazigl.wasm` manually with [Wasmtime](https://wasmtime.dev/) after extracting `<flavor>.tar.zst`, mount `<extracted-dir>/lib` at guest `/lib` (pass `--zig-lib-dir` or set `ZIG_LIB_DIR` when cross-compiling against native target headers):

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

---

## Official Zig Releases (Mirrored from `ziglang.org`)

Stable Zig releases are mirrored automatically and unchanged from <https://ziglang.org/download/>.

Install without specifying a key:

```sh
ghr install cataggar/zig@v0.17.0
```

Or verify the download against the official Zig [minisign](https://jedisct1.github.io/minisign/) public key:

```sh
MINISIGN_PUB=RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U
ghr install cataggar/zig@v0.16.0 $MINISIGN_PUB
ghr install cataggar/zig@v0.17.0 $MINISIGN_PUB
```

---

## Development Releases

Custom native development builds (such as the `libzigc` musl-libc-in-Zig releases, issue #17) are published manually via the `build-release` workflow using stable Zig 0.17.0 as the host compiler and signed with the repository owner's minisign public key:

```sh
MINISIGN_PUB=RWQhfv+qEYWFiUiUqTeTGnyN3KQlTSVNpqhCST5HbBKZRi6SfCJhnVF4
ghr install cataggar/zig@v0.17.0-libc.2 $MINISIGN_PUB
```
