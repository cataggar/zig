#!/usr/bin/env python3
"""Package wazig or wazigl with a Wasm-focused lib/ subset into <flavor>.tar.zst and <flavor>.tar.zst.ghr."""

from __future__ import annotations

import argparse
import fnmatch
import logging
from pathlib import Path
import shutil
import subprocess
import tempfile

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)

VALID_FLAVORS = ("wazig", "wazigl")

REQUIRED_LIB_DIRS = (
    "std",
    "compiler_rt",
    "c",
    "compiler",
    "init",
    "libc/include/wasm-wasi-musl",
    "libc/include/generic-musl",
)

REQUIRED_LIB_FILES = (
    "compiler_rt.zig",
    "c.zig",
    "ubsan_rt.zig",
    "zig.h",
)

CLANG_WASM_INCLUDE_PATTERNS = (
    "__float*.h",
    "__stdarg*.h",
    "__stddef*.h",
    "builtins.h",
    "float.h",
    "inttypes.h",
    "iso646.h",
    "limits.h",
    "stdalign.h",
    "stdarg.h",
    "stdatomic.h",
    "stdbool.h",
    "stdckdint.h",
    "stdcountof.h",
    "stddef.h",
    "stddefer.h",
    "stdint.h",
    "stdnoreturn.h",
    "tgmath.h",
    "unwind.h",
    "vadefs.h",
    "varargs.h",
    "wasm_simd128.h",
)

REQUIRED_CLANG_INCLUDES = (
    "stddef.h",
    "stdint.h",
    "wasm_simd128.h",
)

EXCLUDED_INSTALLED_EXTENSIONS = (
    ".expect",
    ".input",
    ".lzma",
    ".xz",
    ".tzif",
    ".tar",
    ".zip",
    ".idx",
    ".pack",
    ".ghr",
    ".minisig",
)

REQUIRED_ARCHIVE_MEMBERS = (
    "lib/std/std.zig",
    "lib/compiler_rt.zig",
    "lib/c.zig",
    "lib/ubsan_rt.zig",
    "lib/compiler/Maker.zig",
    "lib/compiler/test_runner.zig",
    "lib/compiler/aro/aro.zig",
    "lib/zig.h",
    "lib/init/build.zig",
    "lib/libc/include/wasm-wasi-musl/stdlib.h",
    "lib/libc/include/generic-musl/stdio.h",
    "lib/include/stddef.h",
    "lib/include/stdint.h",
    "lib/include/wasm_simd128.h",
)

FORBIDDEN_ARCHIVE_PREFIXES = (
    "lib/libc/glibc/",
    "lib/libc/mingw/",
    "lib/libc/darwin/",
    "lib/libcxx/",
    "lib/libcxxabi/",
    "lib/libunwind/",
)

GHR_MANIFEST_CONTENT = """.{
    .version = 1,
    .runtime = "wasmtime",
    .runtimeArgs = .{
        "run",
        "-W", "component-model-memory64=y",
        "-W", "component-model-async=y",
        "-W", "component-model-async-stackful=y",
        "-W", "component-model-more-async-builtins=y",
        "-W", "component-model-error-context=y",
        "-W", "max-wasm-stack=67108864",
        "-W", "async-stack-size=67108864",
        "-S", "p3=y",
        "-S", "cli-exit-with-code=y",
        "-S", "inherit-env=y",
        "--dir=${GHR_TOOL_DIR}/lib::/lib",
        "--dir=.",
    },
}
"""


def validate_wasm_binary(wasm_path: Path) -> None:
    """Ensure the staged Wasm compiler binary exists and starts with the Wasm magic bytes."""
    if not wasm_path.is_file():
        raise FileNotFoundError(f"Missing staged Wasm compiler binary: {wasm_path}")
    with wasm_path.open("rb") as f:
        magic = f.read(4)
    if magic != b"\x00asm":
        raise ValueError(f"Invalid WebAssembly magic header in {wasm_path}: {magic!r}")


def stage_wasm_lib_subset(installed_lib_dir: Path, dest_lib_dir: Path) -> None:
    """Copy the Wasm-focused subset of an installed lib/zig directory into dest_lib_dir."""
    if not installed_lib_dir.is_dir():
        raise FileNotFoundError(f"Missing installed Zig library directory: {installed_lib_dir}")

    for rel_dir in REQUIRED_LIB_DIRS:
        src = installed_lib_dir / rel_dir
        if not src.is_dir():
            raise FileNotFoundError(f"Missing required library directory: {src}")
        dst = dest_lib_dir / rel_dir
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(src, dst, symlinks=False)

    for rel_file in REQUIRED_LIB_FILES:
        src = installed_lib_dir / rel_file
        if not src.is_file():
            raise FileNotFoundError(f"Missing required library file: {src}")
        dst = dest_lib_dir / rel_file
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)

    src_include = installed_lib_dir / "include"
    if not src_include.is_dir():
        raise FileNotFoundError(f"Missing compiler include directory: {src_include}")
    dst_include = dest_lib_dir / "include"
    dst_include.mkdir(parents=True, exist_ok=True)

    for entry in sorted(src_include.iterdir()):
        if not entry.is_file():
            continue
        if any(fnmatch.fnmatch(entry.name, pat) for pat in CLANG_WASM_INCLUDE_PATTERNS):
            shutil.copy2(entry, dst_include / entry.name)

    for req_header in REQUIRED_CLANG_INCLUDES:
        if not (dst_include / req_header).is_file():
            raise FileNotFoundError(f"Missing required compiler header in {src_include}: {req_header}")

    # Verify build.zig install filtering is preserved and no forbidden extensions slipped in.
    for path in dest_lib_dir.rglob("*"):
        if not path.is_file():
            continue
        for ext in EXCLUDED_INSTALLED_EXTENSIONS:
            if path.name.endswith(ext):
                raise ValueError(f"Forbidden file extension {ext!r} found in staged library: {path}")


def create_tar_zst(staging_root: Path, flavor: str, archive_path: Path) -> None:
    """Create a deterministic .tar.zst archive with window size <= 8 MiB (wlog <= 23)."""
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    tar_cmd = [
        "tar",
        "--sort=name",
        "--mtime=@0",
        "--owner=0",
        "--group=0",
        "--numeric-owner",
        "-C",
        str(staging_root),
        "-cf",
        "-",
        f"{flavor}.wasm",
        "lib",
    ]
    zstd_cmd = [
        "zstd",
        "-19",
        "--zstd=wlog=23",
        "-T0",
        "-f",
        "-o",
        str(archive_path),
    ]
    with subprocess.Popen(tar_cmd, stdout=subprocess.PIPE) as tar_proc:
        assert tar_proc.stdout is not None
        zstd_res = subprocess.run(zstd_cmd, stdin=tar_proc.stdout, check=False)
        tar_proc.stdout.close()
        tar_rc = tar_proc.wait()
    if tar_rc != 0:
        raise RuntimeError(f"tar exited with status {tar_rc}")
    if zstd_res.returncode != 0:
        raise RuntimeError(f"zstd exited with status {zstd_res.returncode}")


def verify_bundle(archive_path: Path, sidecar_path: Path, flavor: str) -> list[str]:
    """Verify archive integrity, member layout, and sidecar manifest."""
    if not archive_path.is_file():
        raise FileNotFoundError(f"Missing archive: {archive_path}")
    if not sidecar_path.is_file():
        raise FileNotFoundError(f"Missing sidecar manifest: {sidecar_path}")

    subprocess.run(["zstd", "-t", "-q", str(archive_path)], check=True)

    with subprocess.Popen(
        ["zstd", "-dc", str(archive_path)],
        stdout=subprocess.PIPE,
    ) as zstd_proc:
        assert zstd_proc.stdout is not None
        tar_out = subprocess.check_output(["tar", "-tf", "-"], stdin=zstd_proc.stdout, text=True)
        zstd_proc.stdout.close()
        if zstd_proc.wait() != 0:
            raise RuntimeError("zstd decompression failed while listing archive members")

    members = [line.strip().lstrip("./") for line in tar_out.splitlines() if line.strip()]
    member_set = set(members)

    wasm_member = f"{flavor}.wasm"
    if wasm_member not in member_set:
        raise ValueError(f"Archive {archive_path} is missing root {wasm_member}")

    for req in REQUIRED_ARCHIVE_MEMBERS:
        if req not in member_set:
            raise ValueError(f"Archive {archive_path} is missing required member {req}")

    for member in members:
        if member.endswith((".ghr", ".minisig", ".sigstore.json")):
            raise ValueError(f"Archive {archive_path} must not contain sidecar/signature file: {member}")
        if any(member.startswith(prefix) for prefix in FORBIDDEN_ARCHIVE_PREFIXES):
            raise ValueError(f"Archive {archive_path} contains excluded native library path: {member}")

    sidecar_text = sidecar_path.read_text(encoding="utf-8")
    if '"--dir=${GHR_TOOL_DIR}/lib::/lib"' not in sidecar_text:
        raise ValueError(f"Sidecar {sidecar_path} is missing --dir=${{GHR_TOOL_DIR}}/lib::/lib")
    if '"--dir=."' not in sidecar_text:
        raise ValueError(f"Sidecar {sidecar_path} is missing --dir=.")

    return members


def package_bundle(flavor: str, stage_prefix: Path, out_dir: Path) -> tuple[Path, Path]:
    """Stage and package <flavor>.tar.zst and <flavor>.tar.zst.ghr into out_dir."""
    if flavor not in VALID_FLAVORS:
        raise ValueError(f"Unsupported flavor {flavor!r}; expected one of {VALID_FLAVORS}")

    wasm_src = stage_prefix / "bin" / "zig.wasm"
    installed_lib_dir = stage_prefix / "lib" / "zig"
    validate_wasm_binary(wasm_src)

    out_dir.mkdir(parents=True, exist_ok=True)
    for stale in out_dir.glob("*.minisig"):
        raise ValueError(f"Refusing to package while .minisig file exists in {out_dir}: {stale}")

    with tempfile.TemporaryDirectory(prefix=f"stage-{flavor}-", dir=out_dir) as tmp_dir:
        staging_root = Path(tmp_dir)
        shutil.copy2(wasm_src, staging_root / f"{flavor}.wasm")
        stage_wasm_lib_subset(installed_lib_dir, staging_root / "lib")

        archive_path = out_dir / f"{flavor}.tar.zst"
        sidecar_path = out_dir / f"{flavor}.tar.zst.ghr"

        create_tar_zst(staging_root, flavor, archive_path)
        sidecar_path.write_text(GHR_MANIFEST_CONTENT, encoding="utf-8")

    members = verify_bundle(archive_path, sidecar_path, flavor)
    log.info(
        "Packaged %s (%d bytes, %d tar entries) and %s (%d bytes)",
        archive_path,
        archive_path.stat().st_size,
        len(members),
        sidecar_path,
        sidecar_path.stat().st_size,
    )
    return archive_path, sidecar_path


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flavor", required=True, choices=VALID_FLAVORS, help="Release flavor (wazig or wazigl)")
    parser.add_argument(
        "--stage-prefix",
        required=True,
        type=Path,
        help="Path to the installed stage3 prefix containing bin/zig.wasm and lib/zig",
    )
    parser.add_argument(
        "--out-dir",
        default=Path("dist"),
        type=Path,
        help="Output directory for <flavor>.tar.zst and <flavor>.tar.zst.ghr",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    package_bundle(args.flavor, args.stage_prefix, args.out_dir)


if __name__ == "__main__":
    main()
