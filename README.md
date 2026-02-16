# auto-shebang

Upgrade every script's interpreter by changing one symlink. A portable, language-agnostic resolver for shebang-driven scripts — no PATH dependency, no hardcoded paths.

## The problem

Scripts that use an interpreter — Python, Ruby, Node, Perl — need to find it. You've probably tried the standard approaches and hit their limits.

**`#!/usr/bin/env python3`** relies on `$PATH`. PATH varies between users on the same machine, between interactive and non-interactive shells, between SSH sessions and cron jobs, between `sudo` and the invoking user's shell, and between CI environments and developer laptops. A script that works for one person silently finds a different (or no) interpreter for another. This is the most common failure mode, and it's invisible until something breaks.

**`#!/opt/python3.12/bin/python3`** hardcodes a machine-specific path into every script. It works until the interpreter is upgraded, moved, or the script is deployed to a different machine. Then every shebang needs editing. In a project with hundreds of scripts accumulated over years by a growing team, upgrading from Python 3.11 to 3.12 means touching every file. That's not a find-and-replace — it's a PR per repository, code review, merge conflicts with in-flight work, coordinated rollouts across teams, and the near-certainty that some scripts get missed and break silently weeks later. The maintenance burden scales with the number of scripts and never gets easier.

**Virtual environments** solve library isolation but don't solve interpreter location for user-level tools, automation scripts, editor hooks, CI glue, or anything that isn't a managed project with its own venv.

auto-shebang grew out of managing interpreter versions across a large enterprise codebase with hundreds of scripts. It eliminates this entire class of work.

## The solution

Every script in a project resolves to the same interpreter through one symlink. Upgrading 300 scripts from Python 3.11 to 3.12 is one command:

```sh
ln -sf /opt/python3.12/bin/python3 ~/my-project/bin/auto-python
```

Rolling back is the same command with the old path. No files edited, no PRs, no merge conflicts, no scripts missed. You never touch a shebang line again when the interpreter changes.

**How it works:** your shebang points at `auto-python` — a symlink to the `auto-shebang` resolver. When a script runs, the resolver walks up the directory tree from the script's location, finds a symlink named `auto-python` that points to the real Python binary, and exec's it. The resolver replaces itself entirely — it's as if the shebang pointed directly at Python.

```
your-project/
├── bin/
│   └── auto-python → /opt/python3.12/bin/python3    # one symlink
└── scripts/
    ├── deploy.py      ← shebang: #!/usr/bin/env /path/to/auto-python
    ├── test-runner.py  ← same shebang
    └── migrate.py      ← same shebang
```

One symlink controls every script below it in the tree. The search is deterministic, relative to the script's location, and independent of `$PATH`.

auto-shebang is language-agnostic via the **busybox pattern**: when invoked as `auto-python`, it searches for `auto-python` symlinks. When invoked as `auto-ruby`, it searches for `auto-ruby`. Same code, different behavior:

```sh
ln -s auto-shebang /usr/local/bin/auto-python
ln -s auto-shebang /usr/local/bin/auto-ruby
ln -s auto-shebang /usr/local/bin/auto-node
```

## Quick start

### 1. Install auto-shebang and create a language alias

```sh
cp auto-shebang /usr/local/bin/auto-shebang
chmod +x /usr/local/bin/auto-shebang
ln -s auto-shebang /usr/local/bin/auto-python
```

### 2. Create an interpreter symlink in your project

```sh
mkdir -p ~/my-project/bin
ln -s /opt/python3.12/bin/python3 ~/my-project/bin/auto-python
```

### 3. Use it as a shebang

```python
#!/usr/bin/env /usr/local/bin/auto-python

import sys
print(f"Running under: {sys.executable}")
```

When this script runs, `env` invokes `/usr/local/bin/auto-python` (which is really `auto-shebang`). The resolver sees it was invoked as `auto-python`, walks up from the script's directory, finds `bin/auto-python → /opt/python3.12/bin/python3`, and exec's it.

## Living with auto-shebang

The quick start is a one-time setup cost. This section describes the ongoing experience — what you get in return.

### Upgrading the interpreter

```sh
ln -sf /opt/python3.13/bin/python3 ~/my-project/bin/auto-python
```

Every script below `my-project/` picks up the new interpreter immediately. No files to edit. No PRs. No rollout plan.

### Rolling back

```sh
ln -sf /opt/python3.12/bin/python3 ~/my-project/bin/auto-python
```

Same command, old path. Instant rollback, no deployment needed. If the new interpreter breaks something, recovery takes seconds.

### Staged rollout

Test a new interpreter without committing to it. Place it as a secondary symlink alongside the current one:

```sh
ln -s /opt/python3.13/bin/python3 ~/my-project/bin/auto-python-secondary
```

auto-shebang tries candidates in priority order: bare name first (`auto-python`), then `-primary`, `-secondary`, `-tertiary`. Your scripts continue using the current interpreter. To test a specific script against the new one, temporarily override the suffix order:

```sh
AUTO_SHEBANG_SUFFIXES=secondary ./scripts/deploy.py
```

When you're satisfied, promote it:

```sh
ln -sf /opt/python3.13/bin/python3 ~/my-project/bin/auto-python
rm ~/my-project/bin/auto-python-secondary
```

### Adding a new language

One alias at the install location, one interpreter symlink in the project:

```sh
ln -s auto-shebang /usr/local/bin/auto-ruby
ln -s /opt/ruby3.2/bin/ruby ~/my-project/bin/auto-ruby
```

Every Ruby script you write from now on uses the same shebang pattern. Upgrading Ruby works exactly like upgrading Python.

### Adding a new script

Write the shebang, write the script. The interpreter is already configured — zero per-script setup:

```python
#!/usr/bin/env /usr/local/bin/auto-python
print("It just works.")
```

### Per-machine variation

The symlink name is the same everywhere; what it points to can differ per machine. Workstations point to a fast local interpreter, shared servers point to a network-mounted one, CI images point to the build environment's copy. Scripts don't know or care — they all say `auto-python` and get the right interpreter for where they're running.

### Debugging resolution

When something doesn't resolve as expected:

```sh
auto-shebang --debug --resolve auto-python ./scripts/deploy.py
```

This prints the full resolution trace to stderr: effective configuration (with sources for each setting), every candidate checked, and the result.

---

## Common layouts

### Personal scripts and editor hooks

```
~/.cursor/
├── bin/
│   └── auto-python → /opt/python3.12/bin/python3
└── hooks/
    └── transcript.py
```

### Project scripts (most common)

```
my-project/
├── bin/
│   └── auto-python → /opt/python3.12/bin/python3
└── scripts/
    ├── deploy.py
    ├── test-runner.py
    └── migrate.py
```

### Multi-language project

```
my-project/
├── bin/
│   ├── auto-python → /opt/python3.12/bin/python3
│   ├── auto-ruby   → /opt/ruby3.2/bin/ruby
│   └── auto-node   → /opt/node20/bin/node
├── scripts/
│   └── deploy.py
├── config/
│   └── generate.rb
└── tools/
    └── build.js
```

### Monorepo with deep nesting

```
monorepo/
├── bin/
│   └── auto-python → /opt/python3.12/bin/python3
└── services/
    └── api/
        └── scripts/
            └── migrate.py
```

`migrate.py` walks up through `scripts/`, `api/`, `services/`, and finds the interpreter at `monorepo/bin/auto-python`.

### Multi-tier interpreter fallback

```
bin/
├── auto-python           → /opt/local/python3/bin/python3       # fast local
├── auto-python-primary   → /net/shared/python3/bin/python3      # network share
└── auto-python-secondary → /opt/python3.11/bin/python3          # older fallback
```

On machines with the local install, it's fast. On machines without it (dangling symlink), the network interpreter is used automatically.

## Shebang patterns

**Recommended — absolute path to the resolver:**

```python
#!/usr/bin/env /usr/local/bin/auto-python
```

`/usr/bin/env` is used as a binary trampoline. macOS requires shebang targets to be compiled binaries (not scripts). `env` satisfies this while passing through the absolute resolver path. On Linux the trampoline is unnecessary but harmless. One shebang pattern for both platforms.

This avoids `$PATH` entirely. The resolver's path is absolute and machine-specific; the resolver finds the interpreter via relative tree walk. The combination gives reproducibility without fragility.

**Alternative — PATH-based resolver lookup:**

```python
#!/usr/bin/env auto-python
```

Uses `$PATH` to find the resolver, but the resolver still finds the interpreter without `$PATH`. Acceptable for teams that standardize their members' PATH. Not recommended for general distribution.

**Note:** Shebang line length limits vary by platform (128-256 bytes on Linux depending on kernel version). If the absolute path to the resolver exceeds this, the PATH-based pattern is a pragmatic fallback.

## Modes of operation

### Exec mode (default)

The normal shebang use case. The resolver finds the interpreter and replaces itself via `exec`. The original script path is passed to the interpreter unchanged — your script sees the same `argv[0]`, `__file__`, etc., as if auto-shebang wasn't involved.

```sh
./scripts/deploy.py                          # via shebang
auto-python ./scripts/deploy.py arg1 arg2    # explicit
```

### Resolve mode

Print the resolved interpreter path to stdout without executing anything. Useful for build scripts, CI pipelines, and tooling that needs the interpreter path programmatically.

```sh
interpreter=$(auto-shebang --resolve auto-python ./scripts/deploy.py)
```

Safe to run against untrusted scripts — no code from the script is executed.

### Check mode

Exit 0 if an interpreter can be resolved, non-zero if not. Produces no output. Designed for conditionals and CI gating.

```sh
if auto-shebang --check auto-python ./scripts/deploy.py; then
    echo "Ready to deploy"
fi
```

Safe to run against untrusted scripts.

### Library mode

Source `auto-shebang` into your own shell script to use its resolver as a callable function:

```sh
#!/bin/sh
AUTO_SHEBANG_LIB=1
. /path/to/auto-shebang

if auto_shebang_resolve "auto-python" "$1"; then
    echo "Found: $AUTO_SHEBANG_RESULT"
    export PYTHONUNBUFFERED=1
    exec "$AUTO_SHEBANG_RESULT" "$1"
else
    echo "No interpreter found" >&2
    exit 1
fi
```

`AUTO_SHEBANG_LIB=1` prevents auto-execution when sourced. In library mode, internal errors are contained in a subshell — they return an exit code instead of terminating your script.

## How the algorithm works

### The tree walk

Given a script at `/home/user/project/lib/tools/deploy.py`, invoked as `auto-python`:

The resolver starts at the script's directory and walks up one directory at a time until it reaches the filesystem root. At each level, it checks a configurable list of **probe locations** (default: the directory itself, then `bin/`). Within each location, it tries candidate names in **priority order**:

```
/home/user/project/lib/tools/auto-python
/home/user/project/lib/tools/auto-python-primary
/home/user/project/lib/tools/auto-python-secondary
/home/user/project/lib/tools/auto-python-tertiary
/home/user/project/lib/tools/bin/auto-python
/home/user/project/lib/tools/bin/auto-python-primary
    ...
/home/user/project/lib/auto-python
/home/user/project/lib/bin/auto-python
    ...
/home/user/project/auto-python
/home/user/project/bin/auto-python              ← typical match
    ...
(continues to /)
```

A candidate wins if it: exists on disk (not a dangling symlink), is a regular file (`-f`), is executable (`-x`), and is not the resolver itself (detected by inode comparison via `[ file1 -ef file2 ]`).

If the walk reaches `/` without finding anything, resolution fails with an actionable error message that reports exactly what was searched and where.

### Why this works

The search name (`auto-python`) is intentional — no system ships a binary called `auto-python`. Walking all the way to `/` is safe because the name is the namespace. There's no risk of accidentally matching a system binary.

The walk is fast: just stat calls. A typical project nested 5 levels deep with the default probe-dirs (`.:bin`) means ~40 stat calls — negligible even on networked filesystems. No caching is needed, and none is done.

### Path normalization

The script path is normalized to an absolute path before the walk begins, using `cd -P "$(dirname "$path")" && pwd -P` in a subshell. The `-P` flag resolves directory-level symlinks, so the walk origin is always a physical directory. The caller's working directory is not affected.

### Self-detection

The resolver skips itself during the tree walk. If the walk encounters a candidate that is the resolver (by inode comparison with `[ -ef ]`), it moves on. No infinite loops, even when the resolver's install location is an ancestor of the script.

### Priority suffixes

Multiple interpreter symlinks coexist with a defined fallback chain. At each directory level, the bare name is tried first, then `-primary`, `-secondary`, `-tertiary`. If the bare name is a dangling symlink (e.g., local disk not mounted), the next suffix is tried automatically.

The suffix list is configurable via the `auto-shebang-suffixes` directive or `AUTO_SHEBANG_SUFFIXES` env var.

## Configuration

auto-shebang has three layers of configuration, applied in priority order:

1. **Hardcoded defaults** (lowest) — set by the auto-shebang project
2. **Script directives** — set by the script author, embedded in the script
3. **Environment variables** (highest) — set by the deployer or runner

For design rationale behind these choices, see [DESIGN.md](DESIGN.md).

### Script directives

The resolver scans the first 30 lines of the target script for inline directives. A directive is recognized when a line contains `auto-shebang-<key>=<value>`, where `<key>` is a known directive name. The pattern can appear anywhere in the line — the comment character doesn't matter, so it works for any language:

```python
#!/usr/bin/env /path/to/auto-python
# auto-shebang-probe-dirs=.:bin:tools
# auto-shebang-follow-symlinks=no
```

```javascript
#!/usr/bin/env /path/to/auto-node
// auto-shebang-probe-dirs=.:bin
```

The value extends from `=` to the first whitespace character. Trailing comments are fine. If the same key appears multiple times, the last occurrence wins.

#### Available directives

| Directive | Default | Values | Purpose |
|---|---|---|---|
| `auto-shebang-probe-dirs` | `.:bin` | Colon-separated list | Locations to check at each tree-walk level |
| `auto-shebang-suffixes` | `:primary:secondary:tertiary` | Colon-separated list | Suffix search order (leading `:` = include bare name) |
| `auto-shebang-follow-symlinks` | `no` | `yes` or `no` | Enable dual-origin search (see [Advanced](#advanced-dual-origin-search)) |
| `auto-shebang-symlink-priority` | `real-first` | `real-first` or `symlink-first` | Which origin to search first |
| `auto-shebang-trust-env` | `yes` | `yes` or `no` | Honor `AUTO_SHEBANG_*` env vars |
| `auto-shebang-unsafe-expand-probe-dirs` | `no` | `yes` or `no` | Expand `$VAR` in probe-dirs |

**`probe-dirs`** controls which locations are checked and in what order. `.` means the directory itself. What you specify is what you get — no implicit entries. Also supports absolute paths (`/opt/interpreters`), tilde paths (`~/bin`), and relative paths (`../lib`).

**`suffixes`** controls the candidate name search order. A leading `:` means "include the bare name." `:primary` tries bare then `-primary`. `primary:secondary` skips the bare name.

**`trust-env`** when set to `no`, ignores all `AUTO_SHEBANG_*` env vars except `AUTO_SHEBANG_DEBUG`. This directive has no corresponding env var — an env var that disables its own trust would be pointless.

**`unsafe-expand-probe-dirs`** when `yes`, expands `$NAME` and `${NAME}` in probe-dirs from the environment. Only simple variable references — command substitution (`$()`), backticks, and other metacharacters are rejected. Tilde expansion is always available regardless of this setting.

### Environment variables

Each directive has a corresponding env var (except `trust-env`). When set, the env var overrides the directive. Ignored when `trust-env=no`.

| Variable | Overrides | Values |
|---|---|---|
| `AUTO_SHEBANG_PROBE_DIRS` | `probe-dirs` | Colon-separated list |
| `AUTO_SHEBANG_SUFFIXES` | `suffixes` | Colon-separated list |
| `AUTO_SHEBANG_FOLLOW_SYMLINKS` | `follow-symlinks` | `1` or `0` |
| `AUTO_SHEBANG_SYMLINK_PRIORITY` | `symlink-priority` | `real-first` or `symlink-first` |
| `AUTO_SHEBANG_UNSAFE_EXPAND_PROBE_DIRS` | `unsafe-expand-probe-dirs` | `1` or `0` |

Boolean env vars use `1`/`0` (not `yes`/`no`). Invalid values exit 2.

| Variable | Purpose |
|---|---|
| `AUTO_SHEBANG_OVERRIDE_EXE` | Skip tree walk — use this interpreter (checked first) |
| `AUTO_SHEBANG_FALLBACK_EXE` | Use if tree walk finds nothing (checked last) |
| `AUTO_SHEBANG_DEBUG` | Full resolution trace on stderr (always honored, even when `trust-env=no`) |
| `AUTO_SHEBANG_LIB` | Set to `1` when sourcing as library (prevents auto-execution) |

`OVERRIDE_EXE` and `FALLBACK_EXE` are validated like any candidate: must exist, be a regular file, be executable, and not be the resolver itself. A missing path exits 127; a non-executable path exits 126.

## Advanced: dual-origin search

By default, the tree walk starts from the directory of the script as invoked. If the script is a symlink, the walk starts from the symlink's directory, not the real file's directory.

When a script is deployed via symlinks (e.g., `deploy/tool.py → /src/project/tool.py`), the interpreter might be near the real file rather than near the symlink. The `auto-shebang-follow-symlinks=yes` directive enables **dual-origin search**: the resolver follows the symlink chain to find the real file, then searches from *both* locations.

```
/src/project/
├── bin/
│   └── auto-python → /opt/python3/bin/python3
└── tool.py                                        # real file

/deploy/bin/
└── tool.py → /src/project/tool.py                # deployment symlink
```

With `follow-symlinks=yes` and the default `real-first` priority, the resolver searches from `/src/project/` first, then from `/deploy/bin/`. With `symlink-first`, the order reverses.

This feature requires `readlink`. If `readlink` is not available and `follow-symlinks=yes` is set, the resolver exits with error 2 — it does not silently fall back.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success — interpreter found |
| 1 | Not found (check mode only) |
| 2 | Configuration error — invalid directive, bad arguments, missing `readlink` |
| 126 | Interpreter found but not executable |
| 127 | Not found (exec and resolve modes) |

## Platform support

| Platform | Status |
|----------|--------|
| Linux | Fully supported. Tested under dash and bash. |
| macOS | Fully supported. Use `#!/usr/bin/env /path/to/auto-python`. |
| Windows (WSL/Git Bash) | Works under WSL and Git Bash. |
| Windows (native) | Not supported — shebangs are a Unix concept. |

auto-shebang is written in POSIX sh. It runs under dash, ash, bash, ksh, zsh, and busybox sh. In its default configuration, it has no external dependencies beyond standard POSIX utilities.

## Testing

```sh
sh tests/run-tests.sh
```

The test suite creates a temporary workspace with fake interpreters, project structures, and test scripts, then exercises all features: CLI interface, tree walk resolution, directive parsing, configuration precedence, suffix handling, override/fallback behavior, dual-origin search, variable expansion, library mode, error messages, and edge cases (spaces in paths, colons in directory names, leading-dash filenames). 63 tests, portable across POSIX shells.

## License

MIT. See [LICENSE](LICENSE).
