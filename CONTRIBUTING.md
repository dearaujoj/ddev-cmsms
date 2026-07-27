# Contributing to ddev-cmsms

Thanks for helping! This add-on is tested end-to-end against real DDEV
projects, and CI enforces a few things — here's everything you need to know
before opening a PR.

## The one rule CI enforces

**Implementation changes must come with test changes.** A PR that touches
`commands/`, `cmsms/`, or `scripts/` without touching anything under
`tests/` fails the `tests-required` check. If your change genuinely needs
no tests (comment fixes, typos in messages), ask a maintainer to apply the
`no-tests-needed` label — that skips the gate.

All four test-matrix legs (CMSMS 2.2.22 on PHP 8.3/8.1, 2.2.21, 2.2.19) must
also pass before a PR can merge.

## Running the tests locally

Prerequisites: [DDEV ≥ 1.24](https://ddev.readthedocs.io/en/stable/users/install/ddev-installation/)
with a working Docker provider, plus bats with its helper libraries
(`bats-support`, `bats-assert`, `bats-file`).

**macOS and Linux/WSL2 — via [Homebrew](https://brew.sh)** (works identically
on both; this is what CI uses):

```bash
brew install bats-core
brew tap kaos/shell
brew install bats-assert bats-file bats-support
```

**Linux without Homebrew** — install `bats` from your distro
(`apt/dnf install bats`) and clone the helper libraries where the test
suites look for them (`/usr/lib/bats`):

```bash
sudo git clone --depth 1 https://github.com/bats-core/bats-support /usr/lib/bats/bats-support
sudo git clone --depth 1 https://github.com/bats-core/bats-assert  /usr/lib/bats/bats-assert
sudo git clone --depth 1 https://github.com/bats-core/bats-file    /usr/lib/bats/bats-file
```

**Windows**: run the suite inside WSL2 (DDEV's recommended Windows setup)
using either Linux option above.

The tests resolve the library path automatically (`brew --prefix`, falling
back to `/usr/lib/bats`); if yours live elsewhere, set `BATS_LIB_PATH`.

```bash
bats tests                      # full suite (~30+ min: builds real CMSMS sites)
bats tests/test-scaffold.bats   # a single file (the fast ones: scaffold, load, new-project validation)
bats tests/test.bats --filter "db stage"   # a single test (needs the shared project from a prior full run)
```

The suites use long-lived projects under `~/tmp/test-ddev-cmsms*`; the first
test in each file wipes and rebuilds its project. After editing add-on
files, refresh a test project before iterating:
`cd ~/tmp/test-ddev-cmsms && ddev add-on get <absolute path to your clone>`.

## Conventions

- Conventional commit prefixes: `feat:` / `fix:` / `docs:` / `ci:` / `chore:` / `test:`.
- **README documents implemented reality** — when you change a command's
  behavior or flags, update the README in the same commit.
- Host scripts (`commands/host/`, `scripts/`) must run on macOS, Linux,
  WSL2, and git-bash: bash 3.2 is the floor (no bash-4 constructs), and the
  userland must be BSD+GNU portable (`sed -i.bak` with a suffix, no
  GNU-only flags). New external host dependencies need a `command -v`
  guard with an actionable error.
- Every shipped file needs the literal `#ddev-generated` marker (JSON files
  use a `"_comment"` key) or `ddev add-on get` will never update it in
  user projects.
- Before structural changes, read `CLAUDE.md` — its "Hard-won constraints"
  section lists invariants whose violation re-breaks fixed bugs (symlink
  cycles, read-only mounts, the uploads bind-mount, hook exit-0 safety).

## PR flow

1. Fork/branch, make your change plus its tests.
2. Run at least the test file(s) covering what you touched, plus
   `bats tests/test-versions.bats` (fast) as a sanity check.
3. Open the PR — the diff gate and the CI matrix run automatically.
4. A maintainer reviews; the branch protection on `main` requires all
   checks green before merge.

Releases are tagged by maintainers after CI is green on `main`
(`ddev add-on get` serves the latest GitHub release, so users only receive
tagged versions).
