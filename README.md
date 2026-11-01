# WASI 0.3 Hello World with `wazig`

A minimal WASI 0.3 (`wasip3`) WebAssembly Component written in Zig and built directly with [`wazig`](https://github.com/cataggar/zig/releases/tag/v0.17.0-wazig.2) — a WebAssembly (`wasm64-wasip3`) build of the Zig compiler with built-in Component Model packaging.

## Steps

### 1. Install `ghr`

Follow the installation instructions at <https://cataggar.github.io/ghr/>.

### 2. Install `wasmtime` and `wazig`

Install `wasmtime` and the [`v0.17.0-wazig.2`](https://github.com/cataggar/zig/releases/tag/v0.17.0-wazig.2) release of `wazig`:

```sh
ghr install bytecodealliance/wasmtime
ghr install cataggar/zig@v0.17.0-wazig.2
```

### 3. Clone this branch

```sh
git clone -b wazig-hello --single-branch https://github.com/cataggar/zig.git wazig-hello
cd wazig-hello
```

### 4. Build the WASI 0.3 component

```sh
wazig build-exe src/main.zig -target wasm32-wasip3 -O ReleaseSmall -fstrip -femit-bin=hello.wasm
```

### 5. Run with `wasmtime`

```sh
wasmtime run -W component-model-async=y -W component-model-async-stackful=y -W component-model-more-async-builtins=y -S p3=y hello.wasm
```

Output:

```text
Life is not a malfunction.
```
