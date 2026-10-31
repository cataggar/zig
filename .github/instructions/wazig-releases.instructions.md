# `wazig` and `wazigl` Release Descriptions

When creating or updating `wazig*` (`v*-wazig.*` and `v*-wazigl.*`) GitHub release descriptions in `cataggar/zig`:

- Always include a `### Highlights` section summarizing the key changes in that release, using unquoted `#<number>` (or `owner/repo#<number>`) references so GitHub auto-links them.
- `wazigl` (`v*-wazigl.*`) release descriptions must link to the matching `wazig` release (e.g., `Includes everything in [v0.17.0-wazig.N](https://github.com/cataggar/zig/releases/tag/v0.17.0-wazig.N), plus LLVM-specific ...:`) and list **only** LLVM/Clang/LLD-specific highlights under `### Highlights`. Do not duplicate general `wazig` items in `wazigl` release descriptions.
- Both flavors publish unsigned `<flavor>.tar.zst` (containing `<flavor>.wasm` and the Wasm-focused `lib/` subset at archive root) and `<flavor>.tar.zst.ghr` (mounting `--dir=${GHR_TOOL_DIR}/lib::/lib`) assets, with no `.minisig` files.
