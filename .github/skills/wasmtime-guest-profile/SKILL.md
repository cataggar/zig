---
name: wasmtime-guest-profile
description: Profile WebAssembly WASI modules with `wasmtime run --profile=guest`, automatically patching WASI `proc_exit` so Wasmtime flushes the profile JSON, preserving symbol names with `-fno-strip`, ranking functions by self/inclusive samples, diffing two `.wasm` builds (`wazig` vs `zig`), and verifying codegen fixes via in-place `nop`-padded bytecode swaps.
---

# Wasmtime Guest Profiling & Differential Wasm Codegen Analysis (`wasmtime-guest-profile`)

Use this skill when investigating WebAssembly runtime performance (`wasm32-wasi` or `wasm64-wasi*`), comparing `wazig` (`stage2_wasm` `-fno-llvm`) against `zig` (`-fno-llvm` or `-fllvm`), or verifying whether a change in `src/codegen/wasm/CodeGen.zig`, `src/codegen/wasm/Optimize.zig`, or `src/link/Wasm/component/Optimizer.zig` reduces CPU samples in hot functions.

## Critical WASI + Zig Gotchas Solved by This Skill

### 1. `wasi_snapshot_preview1::proc_exit` Suppresses `wasmtime --profile=guest` Output
- Zig's WASI entrypoint `_start` (`lib/std/start.zig`) terminates by calling `std.os.wasi.proc_exit(0); unreachable`.
- In Wasmtime, `proc_exit` unwinds execution via a host `I32Exit(0)` trap rather than returning normally from `_start`. Because `_start` traps out, Wasmtime **skips writing `wasmtime-guest-profile.json`**.
- **Fix (automated by `scripts/wasmtime-profile.py`)**: Locate the import index of `proc_exit` in Wasm Section 2 (`Import`) and patch the 3-byte sequence `call $proc_exit; unreachable` (`0x10 <proc_exit_idx> 0x00`) in Section 10 (`Code`) to `drop; return; unreachable` (`0x1a 0x0f 0x00`) in a temporary copy of the `.wasm` binary. `_start` then returns cleanly and Wasmtime writes the profile JSON.

### 2. `-OReleaseSmall` and `-OReleaseFast` Strip the Wasm `name` Section by Default
- In Zig 0.17, release optimization modes default to `strip = true`, causing `wasmtime --profile=guest` to emit anonymous `<wasm function 2301>` frames instead of symbol names.
- **Fix**: Always append `-fno-strip` after **every** `-OReleaseSmall` / `-OReleaseFast` flag on the command line (or set `.strip = false` on the module in `build.zig`). `-fno-strip` preserves the custom `name` section (`sec_id == 0`, `"name"`) while keeping release codegen (`CodeGen.zig`, `Mir.Optimize`, and `Optimizer.zig`) identical.

### 3. Decoding Wasmtime's Firefox Profiler JSON Schema
- `wasmtime run --profile=guest,profile.json,100us` writes Firefox Profiler JSON (`threads[0].samples.stack` -> `stackTable.frame` + `stackTable.prefix` -> `frameTable.func` -> `funcTable.name` -> `stringArray`).
- `scripts/wasmtime-profile.py` parses this schema to compute both **self samples** (leaf function at top of stack) and **inclusive/total samples** (deduplicated per sample across `stackTable.prefix`), joined with each function's compiled bytecode size from Section 10 (`Code`).

---

## Quick Start (`scripts/wasmtime-profile.py`)

### Step 1 — Compile with `-fno-strip`

Ensure `-fno-strip` follows each `-OReleaseSmall` or `-OReleaseFast` flag so function names are retained:

```bash
# Single-module example:
wazig build-exe -fno-llvm -target wasm32-wasi -OReleaseSmall -fno-strip \
  -Mroot=src/main.zig -femit-bin=app_wazig.wasm
```

### Step 2 — Profile a Single `.wasm` Binary

```bash
python3 .github/skills/wasmtime-guest-profile/scripts/wasmtime-profile.py \
  app_wazig.wasm --interval 100us --top 25 -- --your-guest-args
```

### Step 3 — Diff Two `.wasm` Binaries (`--compare`)

Compare `wazig` against `zig` (or `before.wasm` vs `after.wasm`) and inspect specific functions' bytecode side by side:

```bash
python3 .github/skills/wasmtime-guest-profile/scripts/wasmtime-profile.py \
  app_wazig.wasm --compare app_zig.wasm --interval 100us --top 25 \
  --inspect-func fmaxf --inspect-func fminf \
  -- --scale=1
```

---

## Step 4 — Fast In-Place Bytecode Hypothesis Testing (`nop`-Padded Body Swap)

Before spending time editing `src/codegen/wasm/CodeGen.zig` and rebuilding the compiler, you can validate a codegen hypothesis in 2 seconds by replacing the target function body in Section 10 (`Code`) with a candidate Wasm instruction sequence padded with `nop` (`0x01`) to the **exact same byte length** (so no ULEB128 section or function offsets shift):

```python
from pathlib import Path

# Original 39-byte fmaxf body in stage2_wasm (calls compiler_rt.fmax.fmax_f32):
fmaxf_orig = bytes.fromhex(
    "01037d027d20000c000b2102027d20010c000b210320022003109b122104027d20040c000b0f0b"
)

# Candidate 18-byte branchless IEEE-754 maxNum body (0 locals):
# local.get 0; local.get 1; local.get 0; local.get 1; f32.gt;
# local.get 1; local.get 1; f32.ne; i32.or; select; end
fmaxf_fast = bytes.fromhex("0020002001200020015e200120015c721b0b")

# Pad after the 0x00 local-decl count byte with 0x01 (nop) to keep length == 39:
fmaxf_padded = b"\x00" + b"\x01" * (len(fmaxf_orig) - len(fmaxf_fast)) + fmaxf_fast[1:]
assert len(fmaxf_padded) == len(fmaxf_orig)

wasm_bytes = Path("app_wazig.wasm").read_bytes()
Path("app_wazig_patched.wasm").write_bytes(wasm_bytes.replace(fmaxf_orig, fmaxf_padded, 1))
```

Then run `wasmtime run app_wazig_patched.wasm` to measure the exact wall-clock speedup and verify output checksums before touching compiler source code.

---

## Worked Example (`cataggar/knots#8` -> `cataggar/zig#153`–`#155`)

In `cataggar/knots#8`, `wazig v0.17.0-wazig.3` (`ReleaseSmall`) had smaller bytecode in every user function than `zig 0.17.0 -fno-llvm`, yet `text_bench` took `5.51 ms` on `wazig` vs `3.62 ms` on `zig 0.17.0 -fno-llvm`.

Running `wasmtime-profile.py` with `--compare` immediately exposed why:

```text
Total samples (100us interval): wazig=21,457, zig=14,799
=== TOP SELF-SAMPLE INCREASES (Primary vs Compare) ===
  Delta | Self(P) Self(C) |  Tot(P)  Tot(C) |   Size(P/C) | Function
--------------------------------------------------------------------------------------------------
  +2135 |    2135       0 |    2135       0 |        14/0 | math.signbit.signbit__func_50
  +1936 |    1936       0 |    1936       0 |         8/0 | math.isnan.isNan__func_43
   +590 |    1539     949 |    4001     949 |       39/69 | fmaxf
   +567 |     567       0 |    2674       0 |       141/0 | compiler_rt.fmin.fmin_f32
   +498 |     498       0 |    2462       0 |       141/0 | compiler_rt.fmax.fmax_f32
   +342 |     342       0 |     342       0 |       208/0 | __lshrti3
   +286 |    1369    1083 |    4043    1083 |       39/69 | fminf
   +237 |     237       0 |     409       0 |       106/0 | __multi3
```

1. `src/codegen/wasm/CodeGen.zig:4635` (`floatMax`/`floatMin`) lowers `@max`/`@min` on `f32`/`f64` to `fmaxf`/`fminf` calls in `compiler_rt`.
2. On native `x86_64-linux`, `zig build-exe -fno-llvm` secretly compiled `compiler_rt.a` with LLVM (inlining `fmax_f32`, `isNan`, and `signbit` into a 69-byte leaf `fmaxf`), whereas `wazig` compiled `compiler_rt.a` with `stage2_wasm`, turning every `@max`/`@min` on `f32` into **6 nested function calls** consuming **28.3% of total CPU samples (`6,065 / 21,457`)**.
3. Validating the fix with the Step 4 `nop`-padded swap dropped `text_bench` from `5.51 ms` to **`3.75 ms` (+47% faster)** and `render_bench` from `1.28 ms` to **`1.02 ms` (+26% faster)** with identical checksums, directly motivating `cataggar/zig#153`–`#155`.
