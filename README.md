# cataggar/zig

A personal mirror and build of the [Zig](https://ziglang.org) compiler.

## Branches

- **`master`** — a mirror of the upstream Zig source from
  [codeberg.org/ziglang/zig](https://codeberg.org/ziglang/zig) (the Zig project
  migrated from GitHub to Codeberg). Updated occasionally.
- **`mirror`** (default) — release and CI tooling: the workflows that mirror
  official Zig releases and build the development binaries.

## Releases

Releases here include two kinds of binaries, each signed with a **different
[minisign](https://jedisct1.github.io/minisign/) public key**. Install either
with [`ghr`](https://github.com/cataggar/ghr), passing
the matching public key so the download is signature-verified.

### Official Zig binaries (mirrored from ziglang.org)

Mirrored unchanged from <https://ziglang.org/download/> and verified with the
official Zig minisign key:

```sh
MINISIGN_PUB=RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U
ghr install cataggar/zig@v0.16.0 $MINISIGN_PUB
ghr install cataggar/zig@v0.17.0-dev.813+2153f8143 $MINISIGN_PUB
```

### Development binaries

My own builds (for example the libzigc musl-libc-in-Zig work, issue #17),
signed with my own key:

```sh
MINISIGN_PUB=RWQhfv+qEYWFiUiUqTeTGnyN3KQlTSVNpqhCST5HbBKZRi6SfCJhnVF4
ghr install cataggar/zig@0.17.0-dev.704.libc.1 $MINISIGN_PUB
```
