# Sync Branches

When the user asks to "sync" or "sync branches", perform these steps:

## Remotes

- `origin` — upstream Zig (codeberg.org/ziglang/zig.git)
- `cataggar` — user's GitHub fork (github.com/cataggar/zig.git)
- `github` — user's GitHub fork (github.com/ctaggart/zig.git)
- `codeberg` — user's Codeberg fork (codeberg.org/ctaggart/zig.git)

## Steps

1. Fetch upstream: `git fetch origin`
2. Fast-forward master: `git checkout master && git merge --ff-only origin/master`
3. Push master to GitHub forks: `git push github master && git push cataggar master`
4. Rebase ctmain: `git checkout ctmain && git rebase master`

If the rebase has conflicts, stop and ask the user how to proceed. Do not force-push unless the user explicitly asks.
