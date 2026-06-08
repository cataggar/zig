#!/usr/bin/env python3
"""Download Zig release assets and create a GitHub release."""

# /// script
# requires-python = ">=3.12"
# dependencies = ["requests"]
# ///

import hashlib
import logging
import os
import sys
from pathlib import Path

import requests  # type: ignore[import-untyped]

INDEX_URL = "https://ziglang.org/download/index.json"

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)


def download_file(url: str, dest: Path) -> None:
    """Download a file with progress logging."""
    log.info("  Downloading %s ...", dest.name)
    resp = requests.get(url, stream=True, timeout=600)
    resp.raise_for_status()
    total = int(resp.headers.get("content-length", 0))
    downloaded = 0
    with open(dest, "wb") as f:
        for chunk in resp.iter_content(chunk_size=8 * 1024 * 1024):
            f.write(chunk)
            downloaded += len(chunk)
            if total > 0:
                pct = downloaded * 100 // total
                mb = downloaded // (1024 * 1024)
                log.info("    %d MB (%d%%)", mb, pct)
    log.info("  Saved %s (%d MB)", dest.name, dest.stat().st_size // (1024 * 1024))


def verify_shasum(path: Path, expected: str) -> bool:
    """Verify SHA256 checksum of a downloaded file."""
    sha256 = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8 * 1024 * 1024), b""):
            sha256.update(chunk)
    actual = sha256.hexdigest()
    if actual != expected:
        log.error("  SHA256 MISMATCH for %s: expected %s, got %s", path.name, expected, actual)
        return False
    log.info("  SHA256 OK: %s", path.name)
    return True


def fetch_index() -> dict:
    """Fetch the Zig download index."""
    resp = requests.get(INDEX_URL, timeout=30)
    resp.raise_for_status()
    return resp.json()


def find_release(index: dict, version: str) -> dict | None:
    """Find the release entry matching a version string."""
    for key, release in index.items():
        v = release.get("version", key)
        if v == version:
            return release
    return None


def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <version>")
        print(f"Example: {sys.argv[0]} 0.15.2")
        sys.exit(1)

    version = sys.argv[1]
    # Strip leading "v" if present
    if version.startswith("v"):
        version = version[1:]
    dist_dir = Path("dist")
    dist_dir.mkdir(exist_ok=True)

    log.info("Fetching Zig download index...")
    index = fetch_index()

    release = find_release(index, version)
    if release is None:
        log.error("Version %s not found in index", version)
        sys.exit(1)

    # Metadata keys (not platform entries)
    meta_keys = {"version", "date", "docs", "stdDocs", "notes"}
    platform_keys = [k for k in release if k not in meta_keys]

    log.info("Downloading assets for Zig %s (%d entries)\n", version, len(platform_keys))

    failed: list[str] = []

    for key in platform_keys:
        entry = release[key]
        tarball_url = entry["tarball"]
        shasum = entry.get("shasum", "")
        filename = tarball_url.rsplit("/", 1)[-1]
        dest = dist_dir / filename

        log.info("[%s]", key)

        try:
            # Download the archive
            if dest.exists() and shasum and verify_shasum(dest, shasum):
                log.info("  Already downloaded and verified, skipping")
            else:
                download_file(tarball_url, dest)
                if shasum and not verify_shasum(dest, shasum):
                    failed.append(filename)
                    continue

            # Download the minisig signature
            minisig_url = tarball_url + ".minisig"
            minisig_dest = dist_dir / (filename + ".minisig")
            if not minisig_dest.exists():
                download_file(minisig_url, minisig_dest)

        except Exception as e:
            log.error("  FAILED: %s", e)
            failed.append(filename)

        log.info("")

    if failed:
        log.error("%d downloads failed: %s", len(failed), failed)
        sys.exit(1)

    # List all downloaded files
    files = sorted(dist_dir.iterdir())
    total_size = sum(f.stat().st_size for f in files)
    log.info("Done! %d files in %s/ (%.1f GB total)", len(files), dist_dir, total_size / (1024**3))
    for f in files:
        log.info("  %s (%.1f MB)", f.name, f.stat().st_size / (1024**2))


if __name__ == "__main__":
    main()
