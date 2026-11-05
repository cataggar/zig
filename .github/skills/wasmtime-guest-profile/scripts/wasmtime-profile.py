#!/usr/bin/env python3
"""
wasmtime-profile.py — Profile and compare WebAssembly WASI modules using `wasmtime run --profile=guest`.

Solves two common pitfalls when profiling Zig WASI binaries with Wasmtime:
1. Zig's WASI `_start` calls `wasi_snapshot_preview1::proc_exit(0)`, which raises an
   `I32Exit` trap in Wasmtime and prevents `--profile=guest` from writing its JSON output.
   This script automatically patches `call $proc_exit; unreachable` (`0x10 <idx> 0x00`) in
   a temporary copy of the module to `drop; return; unreachable` (`0x1a 0x0f 0x00`) so
   `_start` returns normally and Wasmtime flushes the profile JSON.
2. Parses Wasmtime's Firefox Profiler JSON format (`stackTable.prefix`, `frameTable.func`,
   `funcTable.name`, `stringArray`) into ranked self and inclusive (total) sample counts,
   with optional side-by-side differential comparison (`--compare`) and per-function
   Wasm bytecode inspection (`--inspect-func`).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


def read_uleb128(data: bytes | bytearray, pos: int) -> tuple[int, int]:
    res = 0
    shift = 0
    while True:
        b = data[pos]
        pos += 1
        res |= (b & 0x7F) << shift
        if (b & 0x80) == 0:
            return res, pos
        shift += 7


def encode_uleb128(val: int) -> bytes:
    out = bytearray()
    while True:
        b = val & 0x7F
        val >>= 7
        if val:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def parse_wasm_functions(wasm_path: Path) -> tuple[dict[str, bytes], int | None]:
    """Return (func_name -> raw_body_bytes, proc_exit_import_index) from a core .wasm file."""
    data = wasm_path.read_bytes()
    if len(data) < 8 or data[:4] != b"\x00asm":
        raise ValueError(f"{wasm_path} is not a valid core WebAssembly module")

    pos = 8
    num_func_imports = 0
    proc_exit_idx: int | None = None
    bodies: list[bytes] = []
    names: dict[int, str] = {}

    while pos < len(data):
        sec_id = data[pos]
        pos += 1
        sec_len, pos = read_uleb128(data, pos)
        sec_end = pos + sec_len

        if sec_id == 2:  # Import section
            cnt, p = read_uleb128(data, pos)
            for _ in range(cnt):
                mlen, p = read_uleb128(data, p)
                p += mlen
                flen, p = read_uleb128(data, p)
                field = data[p : p + flen].decode("utf-8", errors="replace")
                p += flen
                kind = data[p]
                p += 1
                if kind == 0:  # func
                    _, p = read_uleb128(data, p)
                    if field == "proc_exit":
                        proc_exit_idx = num_func_imports
                    num_func_imports += 1
                elif kind == 1:  # table
                    p += 1
                    flags, p = read_uleb128(data, p)
                    _, p = read_uleb128(data, p)
                    if flags & 1:
                        _, p = read_uleb128(data, p)
                elif kind == 2:  # memory
                    flags, p = read_uleb128(data, p)
                    _, p = read_uleb128(data, p)
                    if flags & 1:
                        _, p = read_uleb128(data, p)
                elif kind == 3:  # global
                    p += 2
        elif sec_id == 10:  # Code section
            cnt, p = read_uleb128(data, pos)
            for _ in range(cnt):
                blen, p = read_uleb128(data, p)
                bodies.append(data[p : p + blen])
                p += blen
        elif sec_id == 0:  # Custom section
            nlen, p = read_uleb128(data, pos)
            sname = data[p : p + nlen].decode("utf-8", errors="replace")
            p += nlen
            if sname == "name":
                while p < sec_end:
                    sub_id = data[p]
                    p += 1
                    sub_len, p = read_uleb128(data, p)
                    sub_end = p + sub_len
                    if sub_id == 1:  # function names subsection
                        cnt, q = read_uleb128(data, p)
                        for _ in range(cnt):
                            fidx, q = read_uleb128(data, q)
                            fnlen, q = read_uleb128(data, q)
                            fname = data[q : q + fnlen].decode("utf-8", errors="replace")
                            q += fnlen
                            names[fidx] = fname
                    p = sub_end

        pos = sec_end

    func_map: dict[str, bytes] = {}
    for i, body in enumerate(bodies):
        fidx = num_func_imports + i
        fname = names.get(fidx, f"<wasm function {fidx}>")
        func_map[fname] = body
    return func_map, proc_exit_idx


def patch_proc_exit_for_profiling(in_wasm: Path, out_wasm: Path) -> bool:
    """
    Replace `call $proc_exit; unreachable` (`0x10 <idx> 0x00`) in the Code section with
    `drop; return; unreachable` (`0x1a 0x0f 0x00`) so `_start` returns cleanly and
    Wasmtime flushes its `--profile=guest` profile JSON.
    """
    data = bytearray(in_wasm.read_bytes())
    _, proc_exit_idx = parse_wasm_functions(in_wasm)
    if proc_exit_idx is None or proc_exit_idx >= 128:
        out_wasm.write_bytes(data)
        return False

    pos = 8
    patched_any = False
    pat = bytes([0x10, proc_exit_idx, 0x00])
    rep = bytes([0x1A, 0x0F, 0x00])

    while pos < len(data):
        sec_id = data[pos]
        pos += 1
        sec_len, pos = read_uleb128(data, pos)
        sec_end = pos + sec_len
        if sec_id == 10:
            idx = data.find(pat, pos, sec_end)
            while idx != -1:
                data[idx : idx + 3] = rep
                patched_any = True
                idx = data.find(pat, idx + 3, sec_end)
        pos = sec_end

    out_wasm.write_bytes(data)
    return patched_any


def parse_firefox_profile(prof_json: Path) -> dict[str, Any]:
    """Parse Wasmtime's Firefox Profiler JSON into self and total sample counts per function."""
    raw = json.loads(prof_json.read_text(encoding="utf-8"))
    thread = raw["threads"][0]
    func_table = thread["funcTable"]
    frame_table = thread["frameTable"]
    stack_table = thread["stackTable"]
    samples = thread["samples"]
    strings = thread["stringArray"]

    self_counts: dict[str, int] = {}
    total_counts: dict[str, int] = {}
    valid_samples = 0

    for stack_idx in samples["stack"]:
        if stack_idx is None:
            continue
        valid_samples += 1
        top_frame = stack_table["frame"][stack_idx]
        top_func = frame_table["func"][top_frame]
        top_name = strings[func_table["name"][top_func]]
        self_counts[top_name] = self_counts.get(top_name, 0) + 1

        seen: set[str] = set()
        cur: int | None = stack_idx
        while cur is not None:
            fr = stack_table["frame"][cur]
            fn = frame_table["func"][fr]
            name = strings[func_table["name"][fn]]
            if name not in seen:
                total_counts[name] = total_counts.get(name, 0) + 1
                seen.add(name)
            cur = stack_table["prefix"][cur]

    return {
        "total_samples": valid_samples,
        "self": self_counts,
        "total": total_counts,
    }


def run_wasmtime_guest_profile(
    wasmtime_bin: str,
    wasm_path: Path,
    interval: str,
    wasmtime_flags: list[str],
    guest_args: list[str],
    work_dir: Path,
    label: str,
) -> dict[str, Any]:
    patched_wasm = work_dir / f"{label}_patched.wasm"
    patched = patch_proc_exit_for_profiling(wasm_path, patched_wasm)
    prof_json = work_dir / f"{label}_profile.json"

    cmd = [
        wasmtime_bin,
        "run",
        *wasmtime_flags,
        f"--profile=guest,{prof_json},{interval}",
        str(patched_wasm),
    ]
    if guest_args:
        cmd.extend(["--", *guest_args])

    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"wasmtime failed (exit {proc.returncode}) on {wasm_path}:\n{proc.stderr}"
        )
    if not prof_json.is_file():
        raise RuntimeError(
            f"wasmtime did not produce {prof_json} (proc_exit patched={patched}).\n"
            f"stderr:\n{proc.stderr}"
        )

    funcs, _ = parse_wasm_functions(wasm_path)
    parsed = parse_firefox_profile(prof_json)
    parsed["patched_proc_exit"] = patched
    parsed["func_sizes"] = {k: len(v) for k, v in funcs.items()}
    parsed["func_bodies"] = funcs
    return parsed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Profile and compare WASI .wasm modules with `wasmtime run --profile=guest`."
    )
    parser.add_argument("wasm", type=Path, help="Primary .wasm module to profile (build with -fno-strip).")
    parser.add_argument(
        "--compare",
        type=Path,
        default=None,
        help="Optional reference .wasm module to compare against (e.g. zig -fno-llvm or baseline build).",
    )
    parser.add_argument(
        "--interval",
        default="100us",
        help="Sampling interval passed to --profile=guest (default: 100us).",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=25,
        help="Number of top functions to display (default: 25).",
    )
    parser.add_argument(
        "--wasmtime",
        default=shutil.which("wasmtime") or "wasmtime",
        help="Path to wasmtime binary.",
    )
    parser.add_argument(
        "--wasmtime-arg",
        action="append",
        default=[],
        help="Extra flag to pass to `wasmtime run` (e.g., `--dir=.`, `-W threads=y`). Repeatable.",
    )
    parser.add_argument(
        "--inspect-func",
        action="append",
        default=[],
        help="Inspect bytecode size and hex body for the given function name. Repeatable.",
    )
    parser.add_argument(
        "--json-out",
        type=Path,
        default=None,
        help="Write machine-readable profile summary JSON to this path.",
    )
    parser.add_argument(
        "guest_args",
        nargs=argparse.REMAINDER,
        help="Arguments passed to the guest module after `--`.",
    )

    args = parser.parse_args(argv)
    guest_args = list(args.guest_args)
    if guest_args and guest_args[0] == "--":
        guest_args = guest_args[1:]

    tmp_base = os.environ.get("TMPDIR") or "/tmp"
    with tempfile.TemporaryDirectory(prefix="wasmtime-prof-", dir=tmp_base) as td:
        work_dir = Path(td)
        p1 = run_wasmtime_guest_profile(
            args.wasmtime,
            args.wasm.resolve(),
            args.interval,
            args.wasmtime_arg,
            guest_args,
            work_dir,
            "primary",
        )

        p2 = None
        if args.compare is not None:
            p2 = run_wasmtime_guest_profile(
                args.wasmtime,
                args.compare.resolve(),
                args.interval,
                args.wasmtime_arg,
                guest_args,
                work_dir,
                "compare",
            )

    n1 = p1["total_samples"]
    print(
        f"Primary: {args.wasm} ({n1:,} samples @ {args.interval}, "
        f"proc_exit_patched={p1['patched_proc_exit']})"
    )

    if p2 is None:
        ranked = sorted(
            p1["self"].items(),
            key=lambda kv: (kv[1], p1["total"].get(kv[0], 0)),
            reverse=True,
        )
        print(f"\n=== TOP {args.top} FUNCTIONS BY SELF SAMPLES ===")
        print(f"{'Self':>7} {'Self%':>7} | {'Total':>7} {'Tot%':>7} | {'Bytes':>7} | Function")
        print("-" * 88)
        for fn, sc in ranked[: args.top]:
            tc = p1["total"].get(fn, 0)
            sp = (sc * 100.0 / n1) if n1 else 0.0
            tp = (tc * 100.0 / n1) if n1 else 0.0
            sz = p1["func_sizes"].get(fn, 0)
            print(f"{sc:7d} {sp:6.2f}% | {tc:7d} {tp:6.2f}% | {sz:7d} | {fn}")
    else:
        n2 = p2["total_samples"]
        print(
            f"Compare: {args.compare} ({n2:,} samples @ {args.interval}, "
            f"proc_exit_patched={p2['patched_proc_exit']})"
        )
        all_fns = set(p1["self"].keys()) | set(p2["self"].keys())
        diffs = []
        for fn in all_fns:
            s1 = p1["self"].get(fn, 0)
            s2 = p2["self"].get(fn, 0)
            t1 = p1["total"].get(fn, 0)
            t2 = p2["total"].get(fn, 0)
            diffs.append((s1 - s2, s1, s2, t1, t2, fn))
        diffs.sort(reverse=True)
        print(f"\n=== TOP {args.top} SELF-SAMPLE INCREASES (Primary vs Compare) ===")
        print(
            f"{'Delta':>7} | {'Self(P)':>7} {'Self(C)':>7} | "
            f"{'Tot(P)':>7} {'Tot(C)':>7} | {'Size(P/C)':>11} | Function"
        )
        print("-" * 98)
        for d, s1, s2, t1, t2, fn in diffs[: args.top]:
            sz1 = p1["func_sizes"].get(fn, 0)
            sz2 = p2["func_sizes"].get(fn, 0)
            sz_str = f"{sz1}/{sz2}"
            print(f"{d:+7d} | {s1:7d} {s2:7d} | {t1:7d} {t2:7d} | {sz_str:>11} | {fn}")

    for fn in args.inspect_func:
        print(f"\n=== BYTECODE INSPECTION: {fn} ===")
        b1 = p1["func_bodies"].get(fn, b"")
        print(f"  Primary ({len(b1)} bytes): {b1.hex()}")
        if p2 is not None:
            b2 = p2["func_bodies"].get(fn, b"")
            print(f"  Compare ({len(b2)} bytes): {b2.hex()}")

    if args.json_out is not None:
        out_obj: dict[str, Any] = {
            "primary": {
                "wasm": str(args.wasm),
                "total_samples": p1["total_samples"],
                "self": p1["self"],
                "total": p1["total"],
                "func_sizes": p1["func_sizes"],
            }
        }
        if p2 is not None:
            out_obj["compare"] = {
                "wasm": str(args.compare),
                "total_samples": p2["total_samples"],
                "self": p2["self"],
                "total": p2["total"],
                "func_sizes": p2["func_sizes"],
            }
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(out_obj, indent=2) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
