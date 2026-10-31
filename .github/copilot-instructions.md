# Zig Copilot Instructions

## NEVER create upstream pull requests

The Zig project explicitly bans AI-generated contributions (code, issues, PRs, and comments).
See: https://ziglang.org/news/migrating-from-github-to-codeberg/
See: https://codeberg.org/Codeberg/Community/issues/2458

**Do NOT:**
- Create pull requests targeting codeberg.org/ziglang/zig
- Create issues on codeberg.org/ziglang/zig
- Post comments on codeberg.org/ziglang/zig

All work must stay in the cataggar or ctaggart forks on GitHub. Any upstream
contributions must be manually submitted by a human after thorough review.

## GitHub account usage

The `ctaggart/zig` repo is owned by a different GitHub account. To perform
admin operations (e.g. changing default branch, dispatching workflows), switch
accounts:

```powershell
gh auth switch --user ctaggart   # for ctaggart-owned repos
gh auth switch --user cataggar   # to switch back
```

## `wazig` and `wazigl` release descriptions

When creating or updating `wazig*` (`v*-wazig.*` and `v*-wazigl.*`) GitHub release descriptions in `cataggar/zig`:

- Always include a `### Highlights` section summarizing the key changes in that release, using unquoted `#<number>` (or `owner/repo#<number>`) references so GitHub auto-links them.
- `wazigl` (`v*-wazigl.*`) release descriptions must link to the matching `wazig` release (e.g., `Includes everything in [v0.17.0-wazig.N](https://github.com/cataggar/zig/releases/tag/v0.17.0-wazig.N), plus LLVM-specific ...:`) and list **only** LLVM/Clang/LLD-specific highlights under `### Highlights`. Do not duplicate general `wazig` items in `wazigl` release descriptions.
- Both flavors publish unsigned `<flavor>.tar.zst` (containing `<flavor>.wasm` and `lib/` at archive root) and `<flavor>.tar.zst.ghr` assets, with no `.minisig` files.

