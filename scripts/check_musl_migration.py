#!/usr/bin/env python3
"""Lint commented-out 'migrated to' entries in src/libs/musl.zig.

For each line of the form:

    //"musl/src/<dir>/<name>.c", // migrated to lib/c/<file>.zig

this script verifies that the primary symbol (derived from the C filename)
is exported via a `symbol(..., "NAME")` call somewhere under lib/c/ that is
reachable for non-WASI, non-Windows targets. If not, CI fails — the
"migrated" claim is bogus and the commented line must either be uncommented
or annotated with an explicit exports override.

Override syntax (same line, after the migrated-to clause):

    //"musl/src/stdio/ext2.c", // migrated to lib/c/stdio.zig; exports: __fbufsize,__fpending,...

Exit codes: 0 clean, 1 findings, 2 internal error.
"""
from __future__ import annotations
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
MUSL_ZIG = REPO / "src" / "libs" / "musl.zig"
LIB_C = REPO / "lib" / "c"

# Files that only export for wasi or win32 targets — do NOT count as
# "migrated" for linux-musl / general purposes.
EXCLUDED_FILES = {
    "wasi_sources.zig",
    "wasi_cloudlibc.zig",
    "wasi_thread_stub.zig",
}
EXCLUDED_DIRS = {"win32"}

SYMBOL_RE = re.compile(r'symbol\([^)]*?"([A-Za-z_][A-Za-z0-9_]*)"')
EXPORT_RE = re.compile(r'@export\([^)]*?\.name\s*=\s*"([A-Za-z_][A-Za-z0-9_]*)"')
MIGRATED_RE = re.compile(
    r'^\s*//\s*"(musl/src/[^"]+\.c)"\s*,\s*//\s*migrated to\s+([^\s;]+)'
    r'(?:\s*;\s*exports:\s*([^\n]+))?'
)


def collect_exported_symbols() -> set[str]:
    symbols: set[str] = set()
    for path in LIB_C.rglob("*.zig"):
        rel_parts = path.relative_to(LIB_C).parts
        if path.name in EXCLUDED_FILES:
            continue
        if any(p in EXCLUDED_DIRS for p in rel_parts[:-1]):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            print(f"error: cannot read {path}: {exc}", file=sys.stderr)
            continue
        for m in SYMBOL_RE.finditer(text):
            symbols.add(m.group(1))
        for m in EXPORT_RE.finditer(text):
            symbols.add(m.group(1))
    return symbols


def main() -> int:
    if not MUSL_ZIG.is_file():
        print(f"error: {MUSL_ZIG} not found", file=sys.stderr)
        return 2
    if not LIB_C.is_dir():
        print(f"error: {LIB_C} not found", file=sys.stderr)
        return 2

    exported = collect_exported_symbols()
    if not exported:
        print("error: no symbol() calls found under lib/c", file=sys.stderr)
        return 2

    findings: list[str] = []
    checked = 0
    text = MUSL_ZIG.read_text(encoding="utf-8", errors="replace").splitlines()
    for lineno, line in enumerate(text, start=1):
        m = MIGRATED_RE.match(line)
        if not m:
            continue
        checked += 1
        c_rel = m.group(1)
        target_zig = m.group(2)
        override = m.group(3)
        stem = pathlib.PurePosixPath(c_rel).stem  # "musl/src/a/b.c" -> "b"
        if override:
            expected = [s.strip() for s in override.split(",") if s.strip()]
        else:
            expected = [stem]
        missing = [s for s in expected if s not in exported]
        if missing:
            findings.append(
                f"{MUSL_ZIG.relative_to(REPO).as_posix()}:{lineno}: "
                f'"{c_rel}" claims "migrated to {target_zig}" but '
                f"symbol(s) {missing} are not exported anywhere under lib/c "
                f"(excluding wasi_*.zig and win32/). "
                "Either uncomment the C file, or annotate the line with "
                "`; exports: <name1>,<name2>,...` to document the real "
                "export names."
            )

    if findings:
        print(
            f"musl.zig migration lint: {len(findings)} problem(s) "
            f"out of {checked} 'migrated to' entries checked "
            f"({len(exported)} symbols found under lib/c):",
            file=sys.stderr,
        )
        for f in findings:
            print(f, file=sys.stderr)
        return 1

    print(
        f"musl.zig migration lint: OK "
        f"({checked} 'migrated to' entries, {len(exported)} symbols under lib/c)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
