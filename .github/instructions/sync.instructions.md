# Sync Branches

When the user asks to "sync" or "sync branches", perform these steps:

## Remotes

- `origin` — upstream Zig (codeberg.org/ziglang/zig.git)
- `ctaggart` — user's GitHub fork (github.com/ctaggart/zig.git) — PR target, hosts `ai` infra branch
- `cataggar` — user's GitHub CI-pool fork (github.com/cataggar/zig.git)
- `codeberg` — user's Codeberg fork (codeberg.org/ctaggart/zig.git)

## Branches

- `master` — mirrors upstream. Never commit fork-specific changes here.
- `ai` — default branch on `ctaggart/zig`. Hosts all fork-infra workflows
  (`test-libc.yml`, `check-release.yml`, `publish.yml`, `daily-repo-status.*`)
  and Copilot instructions.
- `libc/<version>` — release-track branches for libzigc releases.
- `combined` — CI aggregation branch of libzigc migrations.
- `libzigc-*` — individual migration feature branches.

Note: `ctmain` and `ci` were retired; everything consolidated onto `ai`.

## Steps

1. Fetch upstream: `git fetch origin`
2. Fast-forward master: `git checkout master && git merge --ff-only origin/master`
3. Push master to GitHub forks: `git push ctaggart master && git push cataggar master`

If the merge is not a fast-forward, stop and ask the user how to proceed. Do not force-push unless the user explicitly asks.
