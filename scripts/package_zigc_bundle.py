#!/usr/bin/env python3
"""Package native Linux zigc (-Dflat -Dno-langref) into zigc-<target>-<version>.tar.zst."""

from __future__ import annotations

import argparse
import logging
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)

TARGET_ELF_MACHINE: dict[str, int] = {
    "x86_64-linux": 62,  # EM_X86_64
    "aarch64-linux": 183,  # EM_AARCH64
}
VALID_TARGETS = tuple(TARGET_ELF_MACHINE.keys())

ELF64_EHDR_STRUCT = struct.Struct("<16sHHIQQQIHHHHHH")
ET_EXEC = 2
ET_DYN = 3
PT_INTERP = 3

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

REQUIRED_REL_MEMBERS = (
    "zigc",
    "LICENSE",
    "README.md",
    "lib/std/std.zig",
    "lib/compiler_rt.zig",
    "lib/c.zig",
    "lib/ubsan_rt.zig",
    "lib/compiler/Maker.zig",
    "lib/compiler/test_runner.zig",
    "lib/compiler/aro/aro.zig",
    "lib/zig.h",
    "lib/init/build.zig",
    "lib/libc/include/generic-musl/stdio.h",
    "lib/libc/include/wasm-wasi-musl/stdlib.h",
    "lib/include/stddef.h",
    "lib/include/stdint.h",
)


def validate_version(version: str) -> None:
    """Ensure version string is non-empty and safe for directory/archive naming."""
    if not version or any(ch in version for ch in ("/", "\\", "\x00")) or any(ch.isspace() for ch in version):
        raise ValueError(f"Invalid version string: {version!r}")
    if version.startswith("v"):
        raise ValueError(f"Version string {version!r} must not start with 'v' (expected e.g. '0.17.1-zigc.1')")


def validate_static_elf64_binary(exe_path: Path, target: str) -> None:
    """Ensure exe_path is a static little-endian ELF64 executable matching target."""
    if target not in TARGET_ELF_MACHINE:
        raise ValueError(f"Unsupported target {target!r}; expected one of {VALID_TARGETS}")
    if not exe_path.is_file():
        raise FileNotFoundError(f"Missing staged compiler binary: {exe_path}")

    with exe_path.open("rb") as f:
        ehdr_bytes = f.read(ELF64_EHDR_STRUCT.size)
        if len(ehdr_bytes) < ELF64_EHDR_STRUCT.size:
            raise ValueError(f"Binary {exe_path} is too small to be an ELF64 executable ({len(ehdr_bytes)} bytes)")

        (
            e_ident,
            e_type,
            e_machine,
            _e_version,
            _e_entry,
            e_phoff,
            _e_shoff,
            _e_flags,
            _e_ehsize,
            e_phentsize,
            e_phnum,
            _e_shentsize,
            _e_shnum,
            _e_shstrndx,
        ) = ELF64_EHDR_STRUCT.unpack(ehdr_bytes)

        if e_ident[:4] != b"\x7fELF":
            raise ValueError(f"Invalid ELF magic header in {exe_path}: {e_ident[:4]!r}")
        if e_ident[4] != 2 or e_ident[5] != 1 or e_ident[6] != 1:
            raise ValueError(f"Expected little-endian ELF64 v1 header in {exe_path}, got e_ident={e_ident[:7]!r}")
        if e_type not in (ET_EXEC, ET_DYN):
            raise ValueError(f"Expected ELF executable (ET_EXEC/ET_DYN) in {exe_path}, got e_type={e_type}")

        expected_machine = TARGET_ELF_MACHINE[target]
        if e_machine != expected_machine:
            raise ValueError(
                f"ELF e_machine mismatch for {target} in {exe_path}: expected {expected_machine}, got {e_machine}"
            )

        if e_phnum > 0:
            if e_phentsize < 56:
                raise ValueError(f"Invalid ELF64 program header entry size in {exe_path}: {e_phentsize}")
            f.seek(e_phoff)
            phdr_table = f.read(e_phnum * e_phentsize)
            if len(phdr_table) < e_phnum * e_phentsize:
                raise ValueError(f"Truncated ELF64 program header table in {exe_path}")
            for i in range(e_phnum):
                (p_type,) = struct.unpack_from("<I", phdr_table, i * e_phentsize)
                if p_type == PT_INTERP:
                    raise ValueError(f"Expected statically linked ELF binary in {exe_path}, found PT_INTERP segment")


def stage_zigc_bundle(stage_prefix: Path, bundle_dir: Path, target: str) -> None:
    """Stage zig -> zigc, LICENSE, README.md, and full lib/ into bundle_dir."""
    if not stage_prefix.is_dir():
        raise FileNotFoundError(f"Missing stage prefix directory: {stage_prefix}")
    if (stage_prefix / "doc").exists():
        raise ValueError(f"Unexpected doc/ directory in {stage_prefix}; build with -Dno-langref")

    exe_src = stage_prefix / "zig"
    if not exe_src.is_file():
        alt = stage_prefix / "zigc"
        if alt.is_file():
            exe_src = alt
    validate_static_elf64_binary(exe_src, target)

    lib_src = stage_prefix / "lib"
    if not lib_src.is_dir():
        raise FileNotFoundError(f"Missing flat lib/ directory in {stage_prefix}: {lib_src}")

    bundle_dir.mkdir(parents=True, exist_ok=True)
    exe_dst = bundle_dir / "zigc"
    shutil.copy2(exe_src, exe_dst)
    exe_dst.chmod(0o755)

    for top_file in ("LICENSE", "README.md"):
        src = stage_prefix / top_file
        if not src.is_file():
            raise FileNotFoundError(f"Missing required flat bundle file: {src}")
        shutil.copy2(src, bundle_dir / top_file)

    lib_dst = bundle_dir / "lib"
    shutil.copytree(lib_src, lib_dst, symlinks=False)

    for path in lib_dst.rglob("*"):
        if not path.is_file():
            continue
        for ext in EXCLUDED_INSTALLED_EXTENSIONS:
            if path.name.endswith(ext):
                raise ValueError(f"Forbidden file extension {ext!r} found in staged library: {path}")


def create_tar_zst(staging_root: Path, bundle_name: str, archive_path: Path) -> None:
    """Create a deterministic .tar.zst archive with window size <= 8 MiB (wlog <= 23) for ghr."""
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
        bundle_name,
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


def verify_bundle(archive_path: Path, target: str, version: str) -> list[str]:
    """Verify .tar.zst archive integrity and expected member layout."""
    validate_version(version)
    if target not in VALID_TARGETS:
        raise ValueError(f"Unsupported target {target!r}; expected one of {VALID_TARGETS}")
    if not archive_path.is_file():
        raise FileNotFoundError(f"Missing archive: {archive_path}")

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

    bundle_name = f"zigc-{target}-{version}"
    bundle_prefix = f"{bundle_name}/"
    members = [line.strip().lstrip("./") for line in tar_out.splitlines() if line.strip()]
    member_set = set(members)

    for member in members:
        if member != bundle_name and not member.startswith(bundle_prefix):
            raise ValueError(f"Archive {archive_path} contains member outside {bundle_prefix}: {member}")
        if member.endswith((".ghr", ".minisig", ".sigstore.json")):
            raise ValueError(f"Archive {archive_path} must not contain sidecar/signature file: {member}")
        if member == f"{bundle_prefix}zig":
            raise ValueError(f"Archive {archive_path} must rename 'zig' binary to 'zigc'")
        if member == f"{bundle_prefix}doc" or member.startswith(f"{bundle_prefix}doc/"):
            raise ValueError(f"Archive {archive_path} must not include doc/ (-Dno-langref)")

    for rel in REQUIRED_REL_MEMBERS:
        expected = f"{bundle_prefix}{rel}"
        if expected not in member_set:
            raise ValueError(f"Archive {archive_path} is missing required member {expected}")

    return members


def package_bundle(target: str, version: str, stage_prefix: Path, out_dir: Path) -> Path:
    """Stage and package zigc-<target>-<version>.tar.zst into out_dir."""
    if target not in VALID_TARGETS:
        raise ValueError(f"Unsupported target {target!r}; expected one of {VALID_TARGETS}")
    validate_version(version)

    out_dir.mkdir(parents=True, exist_ok=True)
    for stale in out_dir.glob("*.minisig"):
        raise ValueError(f"Refusing to package while .minisig file exists in {out_dir}: {stale}")

    bundle_name = f"zigc-{target}-{version}"
    archive_path = out_dir / f"{bundle_name}.tar.zst"

    with tempfile.TemporaryDirectory(prefix=f"stage-{bundle_name}-", dir=out_dir) as tmp_dir:
        staging_root = Path(tmp_dir)
        stage_zigc_bundle(stage_prefix, staging_root / bundle_name, target)
        create_tar_zst(staging_root, bundle_name, archive_path)

    members = verify_bundle(archive_path, target, version)
    log.info(
        "Packaged %s (%d bytes, %d tar entries)",
        archive_path,
        archive_path.stat().st_size,
        len(members),
    )
    return archive_path


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True, choices=VALID_TARGETS, help="Linux target (x86_64-linux or aarch64-linux)")
    parser.add_argument(
        "--version",
        required=True,
        help="Version string without leading 'v' (e.g. 0.17.1-zigc.1)",
    )
    parser.add_argument(
        "--stage-prefix",
        required=True,
        type=Path,
        help="Path to the -Dflat -Dno-langref stage prefix containing zig, lib/, LICENSE, and README.md",
    )
    parser.add_argument(
        "--out-dir",
        default=Path("dist"),
        type=Path,
        help="Output directory for zigc-<target>-<version>.tar.zst",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    package_bundle(args.target, args.version, args.stage_prefix, args.out_dir)


if __name__ == "__main__":
    main()
