#!/usr/bin/env python3
"""Check for new Zig releases and signal when a new tag should be created."""

# /// script
# requires-python = ">=3.12"
# dependencies = ["requests"]
# ///

import json
import logging
import os
import sys

import requests  # type: ignore[import-untyped]

INDEX_URL = "https://ziglang.org/download/index.json"

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)


def github_headers() -> dict[str, str]:
    """Build headers for GitHub API requests."""
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    token = os.environ.get("GITHUB_TOKEN", "")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def tag_exists(repo: str, tag: str) -> bool:
    """Check if a git tag already exists in our repository."""
    url = f"https://api.github.com/repos/{repo}/git/ref/tags/{tag}"
    resp = requests.get(url, headers=github_headers(), timeout=30)
    if resp.status_code == 200:
        return True
    if resp.status_code == 404:
        return False
    resp.raise_for_status()
    return False


def set_github_output(name: str, value: str) -> None:
    """Write a key=value pair to $GITHUB_OUTPUT."""
    output_file = os.environ.get("GITHUB_OUTPUT")
    if output_file:
        with open(output_file, "a") as f:
            f.write(f"{name}={value}\n")
    else:
        log.info("GITHUB_OUTPUT not set (running locally?); would set %s=%s", name, value)


def fetch_index() -> dict:
    """Fetch the Zig download index."""
    resp = requests.get(INDEX_URL, timeout=30)
    resp.raise_for_status()
    return resp.json()


def main() -> None:
    our_repo = os.environ.get("GITHUB_REPOSITORY", "cataggar/zig")
    log.info("Checking for new Zig releases...")

    index = fetch_index()
    new_versions: list[str] = []

    for key, release in index.items():
        version = release.get("version", "")
        if not version:
            # Older releases use the key as the version
            version = key

        # Skip if it looks like "master" and has no real version
        if version == "master":
            continue

        # For stable releases, tag as "v0.15.2"; for dev builds, "v0.16.0-dev.2962+08416b44f"
        tag_name = f"v{version}"

        if tag_exists(our_repo, tag_name):
            log.info("Tag %s already exists — skipping", tag_name)
            continue

        # Check that the release has at least some platform tarballs
        platform_count = sum(1 for k in release if k not in ("version", "date", "docs", "stdDocs", "src", "bootstrap", "notes"))
        if platform_count < 3:
            log.warning("Release %s has only %d platforms — skipping", version, platform_count)
            continue

        log.info("New release found: %s (%d platforms)", version, platform_count)
        new_versions.append(tag_name)

    if not new_versions:
        log.info("No new releases found")
        set_github_output("new_versions", "")
        return

    # Output as JSON array for matrix strategy
    versions_json = json.dumps(new_versions)
    log.info("New versions to publish: %s", versions_json)
    set_github_output("new_versions", versions_json)


if __name__ == "__main__":
    main()
