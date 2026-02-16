# auto-shebang

A single-file, language-agnostic interpreter resolver for scripts. No PATH gambling, no hardcoded shebangs.

## The problem

Scripts that use an interpreter (Python, Ruby, Node, Perl, etc.) need to find that interpreter. The standard options are all bad:

| Approach | Failure mode |
|---|---|
| `#!/usr/bin/env python3` | Relies on `$PATH`, which varies across users, machines, cron jobs, SSH sessions, and CI environments |
| `#!/opt/specific/path/python3` | Hardcodes a machine-specific path into every script |
| Virtual environments | Correct for project dependencies, but user-level tools and automation shouldn't live in a venv |

## The solution

`auto-shebang` finds the interpreter by walking up the directory tree from the calling script, looking for **symlinks whose name matches the resolver's invocation name**. The name is intentional and unambiguous — it never collides with system-installed interpreters.

One script handles every language via the busybox pattern: install `auto-shebang` once, then create language-specific symlinks:

```bash
ln -s auto-shebang ~/.local/bin/auto-python
ln -s auto-shebang ~/.local/bin/auto-ruby
ln -s auto-shebang ~/.local/bin/auto-node
```

When invoked as `auto-python`, it searches for `auto-python` interpreter symlinks. When invoked as `auto-ruby`, it searches for `auto-ruby`. Same code, different behavior.

### Resolution algorithm

Starting from the script's directory and walking up to the filesystem root:

1. **At each directory level**, check:
   - The directory itself
   - Each subdirectory in the probe list (default: `bin`)

2. **Within each location**, try these names in order:
   - `auto-python` (or whatever the invocation name is)
   - `auto-python-primary`
   - `auto-python-secondary`
   - `auto-python-tertiary`

3. If the tree walk is exhausted, check `$AUTO_PYTHON` (derived from the invocation name) as a final explicit fallback.

4. **Fail with a clear error message** — never silently falls back to an unknown interpreter.

The first candidate that exists, resolves to a real file (not a dangling symlink), is executable, and is not the resolver itself wins.

## Quick start

### 1. Install auto-shebang

```bash
cp auto-shebang ~/.local/bin/auto-shebang
chmod +x ~/.local/bin/auto-shebang
ln -s auto-shebang ~/.local/bin/auto-python
```

Or wherever your team keeps shared tools (`/opt/tools/bin/`, `/projects/shared/bin/`, etc.).

### 2. Create an interpreter symlink

Place a symlink named `auto-python` where the tree walk will find it:

```bash
mkdir -p ~/project/bin
ln -sf /opt/python3.12/bin/python3 ~/project/bin/auto-python
```

### 3. Use it as a shebang

```python
#!/usr/bin/env /home/user/.local/bin/auto-python

import sys
print(f"Running: {sys.executable}")
```

`/usr/bin/env` acts as a binary trampoline: macOS requires shebang targets to be compiled binaries (not scripts), and `env` satisfies this. On Linux the trampoline is unnecessary but harmless. One pattern for both platforms.

**Alternative — PATH-based resolver lookup:**

```python
#!/usr/bin/env auto-python
```

Uses `$PATH` to find the resolver (but the resolver still finds the interpreter *without* using `$PATH`). Useful when the resolver's absolute path varies across machines.

**Alternative — polyglot preamble (Python-specific):**

```python
#!/bin/bash
"true" '''\'
exec auto-python "$0" "$@"
'''

import sys
print(f"Running: {sys.executable}")
```

The preamble is simultaneously valid bash and valid Python. Use when neither the resolver's absolute path nor `#!/usr/bin/env` is viable.

## How it works

### Example resolution

Script at `/home/user/project/lib/tools/deploy.py`, invoked via `auto-python`:

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
$AUTO_PYTHON                                     ← env var fallback
FAIL                                             ← actionable error
```

### Self-detection

The resolver skips itself during the tree walk. If `auto-python` (the resolver symlink) is at `~/.local/bin/auto-python` and the tree walk reaches that directory, it detects the candidate is itself (by inode comparison) and moves on. No infinite loops.

## Common layouts

### User-level tools (personal scripts, editor hooks)

```
~/.cursor/
├── bin/
│   └── auto-python → /opt/python3.12/bin/python3
└── hooks/
    └── transcript.py  (shebang: #!/usr/bin/env /home/user/.local/bin/auto-python)
```

Resolution: `transcript.py` → walk up to `.cursor/` → `bin/auto-python` → found.

### Project scripts

```
my-project/
├── bin/
│   └── auto-python → /opt/python3.12/bin/python3
└── scripts/
    ├── deploy.py
    └── test-runner.py
```

Resolution: `deploy.py` → walk up to `my-project/` → `bin/auto-python` → found.

### Deep nesting (monorepo)

```
monorepo/
├── bin/
│   └── auto-python → /opt/python3.12/bin/python3
└── services/
    └── api/
        └── scripts/
            └── migrate.py
```

Resolution: `migrate.py` → walks up through `scripts/`, `api/`, `services/` → reaches `monorepo/` → `bin/auto-python` → found.

### Multi-language project

```
my-project/
├── bin/
│   ├── auto-python → /opt/python3.12/bin/python3
│   ├── auto-ruby → /opt/ruby3.2/bin/ruby
│   └── auto-node → /opt/node20/bin/node
├── scripts/
│   ├── deploy.py      (shebang: #!/usr/bin/env .../auto-python)
│   └── provision.rb   (shebang: #!/usr/bin/env .../auto-ruby)
└── tools/
    └── build.js       (shebang: #!/usr/bin/env .../auto-node)
```

One `bin/` directory, one symlink per language.

## Priority suffixes

Multiple interpreters can coexist with a well-defined fallback chain:

```
bin/
├── auto-python             → /opt/local/python3.12/bin/python3  (fast local)
├── auto-python-primary     → /net/shared/python3.12/bin/python3 (network)
├── auto-python-secondary   → /opt/python3.11/bin/python3        (older version)
└── auto-python-tertiary    → /emergency/python3/bin/python3     (last resort)
```

At each directory level, `auto-python` is tried first. If it doesn't exist or is a dangling symlink (local disk not mounted), `auto-python-primary` is tried next, and so on.

**Use case:** `auto-python` points to a fast interpreter on local SSD. `auto-python-primary` points to the same version on a network share. On machines with the local install, it's fast. On machines without it, it still works via the network — no configuration changes needed.

## Changing the interpreter

Update one symlink, and every script below it in the tree picks up the change immediately:

```bash
ln -sf /opt/python3.13/bin/python3 ~/project/bin/auto-python
```

No files to edit, no scripts to re-deploy.

## Configuration

### `AUTO_SHEBANG_PROBE_DIRS`

Colon-separated list of subdirectory names to check at each tree level. Default: `bin`.

```bash
AUTO_SHEBANG_PROBE_DIRS=bin:venv/bin:scripts ./myscript.py
```

### `AUTO_SHEBANG_DEBUG`

Set to `1` to print the full resolution trace to stderr:

```bash
$ AUTO_SHEBANG_DEBUG=1 auto-python ./myscript.py
auto-python: script: ./myscript.py
auto-python: script_dir: /home/user/project
auto-python: search_name: auto-python
auto-python: probe_dirs: bin
auto-python:   skip: /home/user/project/auto-python
auto-python:   skip: /home/user/project/auto-python-primary
...
auto-python: resolved: /home/user/project/bin/auto-python
```

### Language-specific env vars

The resolver derives an environment variable name from its invocation name by uppercasing and replacing hyphens with underscores:

| Invocation | Env var |
|---|---|
| `auto-python` | `$AUTO_PYTHON` |
| `auto-ruby` | `$AUTO_RUBY` |
| `auto-node` | `$AUTO_NODE` |

These are checked after the tree walk is exhausted — they act as a fallback, not an override:

```bash
AUTO_PYTHON=/opt/debug-python/bin/python3 ./myscript.py
```

## Error messages

When no interpreter is found:

```
auto-python: no valid interpreter found for: ./scripts/deploy.py

Searched from /home/user/project/scripts to / for:
  auto-python, auto-python-primary, auto-python-secondary, auto-python-tertiary
In each directory and subdirectories: bin

Expected location (nearest to script):
  /home/user/project/scripts/../bin/auto-python

Create the interpreter symlink:
  mkdir -p "/home/user/project/bin"
  ln -sf /path/to/interpreter "/home/user/project/bin/auto-python"

Or set $AUTO_PYTHON for a one-off override:
  AUTO_PYTHON=/path/to/interpreter ./scripts/deploy.py
```

## Platform support

| Platform | Status |
|---|---|
| Linux | Fully supported |
| macOS | Fully supported (bash 3.2+) |
| Windows (WSL) | Works in WSL and Git Bash |
| Windows (native) | Not supported — use WSL or Git Bash |

The standard shebang `#!/usr/bin/env /path/to/auto-python` works on both Linux and macOS. auto-shebang is written in POSIX sh — it runs under dash, ash, bash, ksh, zsh, and busybox sh. It does **not** use `readlink -f` or other GNU-specific tools.

> **Note:** On Linux, `#!/path/to/auto-python` also works directly (the kernel handles script-as-interpreter). macOS requires the shebang target to be a compiled binary, which is why `env` is used as a trampoline. The `env` form works on both, so we recommend it universally.

## License

MIT. See [LICENSE](LICENSE).
