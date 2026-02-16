# Design

This document explains the design rationale behind auto-shebang — why it works the way it does, what was considered and rejected, and what is explicitly out of scope. For usage documentation, see [README.md](README.md).

## Threat model

auto-shebang is designed for developer and deployment scripts running as an unprivileged user. The baseline assumptions are:

- The user running the script controls their own environment.
- The filesystem near the script is not attacker-controlled.
- `$PATH` is unreliable for shared software deployment in multi-user environments where correctness and reproducibility are critical.

auto-shebang is **not** designed for setuid or privilege-escalation contexts. The `auto-shebang-trust-env=no` directive disables all `AUTO_SHEBANG_*` environment variable overrides, but does not make auto-shebang safe for privileged execution. Other environment variables (`HOME`, `PATH`) inherently influence shell script behavior and are not controlled by this setting.

Check and resolve modes are safe to run against untrusted scripts — they parse directives from the script (pure text matching) but do not execute any code from it.

## Architecture

auto-shebang is a single POSIX sh script organized as a set of functions with a source guard at the bottom.

```
auto_shebang_parse_directives(script)
    Scan first 30 lines for auto-shebang-<key>=<value>.
    Value: = to first whitespace. Strip \r. Known keys only;
    unknown keys logged under debug. Last occurrence wins.
    Boolean values must be exactly yes/no; invalid → exit 2.

auto_shebang_build_config()
    Layer defaults → directives → env vars (if trust-env=yes).
    Boolean env vars map 1/0 → yes/no.

auto_shebang_normalize_path(path)
    Absolute path via cd -P / pwd -P in a subshell.
    Resolves directory symlinks. Preserves caller's cwd.
    Pure POSIX — no readlink dependency.

auto_shebang_expand_vars(string)
    Safe substitution: $NAME and ${NAME} from environment.
    Rejects command substitution ($()), backticks.
    Glob characters are not rejected but do not expand
    because all expanded values are used in quoted contexts.

auto_shebang_expand_probe_entry(entry, walk_dir)
    Normalize one probe-dirs entry:
    ~ → $HOME (always). $VAR expansion (if unsafe-expand
    enabled). Absolute → use as-is. Relative → join with
    walk_dir.

auto_shebang_resolve_symlink(path)
    Follow symlink chain via single-level readlink in a loop.
    Max 40 hops (matches Linux SYMLOOP_MAX). Relative targets
    resolved against containing directory, not cwd.
    Only called when follow-symlinks=yes.

auto_shebang_validate_exe(path)
    Check -f, -x, not-self (via [ -ef ]). Exit 126 if
    not executable, 127 if not found.

auto_shebang_walk(start_dir, search_name, probe_dirs, suffixes)
    Tree walk from start_dir to /. At each level, iterate
    probe-dirs; absolute entries checked at their ordinal
    position on the first level only. Try each suffix at
    each location. First valid candidate wins.

_as_resolve_core(search_name, script_path)
    Orchestrate: parse directives → build config →
    check OVERRIDE_EXE → normalize path → resolve symlinks →
    walk origin 1 → walk origin 2 → check FALLBACK_EXE → fail.

auto_shebang_resolve(search_name, script_path)
    Public wrapper. In library mode (AUTO_SHEBANG_LIB=1),
    runs _as_resolve_core in a subshell to contain exit calls.
    Sets AUTO_SHEBANG_RESULT. Returns 0 or propagates exit code.

auto_shebang_main()
    Parse CLI flags (--resolve, --check, --version, --help,
    --debug). Dispatch to resolve → exec/print/check.

source guard
    Call main unless AUTO_SHEBANG_LIB=1.
```

## Resolution algorithm

Resolution proceeds in this order:

1. **Parse directives** from the script (first 30 lines). Determine `trust-env`.
2. **Build effective config.** For each setting: hardcoded default, then directive if present, then env var if present and `trust-env=yes`.
3. If `trust-env=yes` and `$AUTO_SHEBANG_OVERRIDE_EXE` is set, validate and use it. Done.
4. **Normalize** script path to absolute (`cd -P`/`pwd -P` in a subshell).
5. **Resolve symlink origins** if `follow-symlinks=yes` (requires `readlink`).
6. **Tree walk** from primary origin to `/`.
7. **Tree walk** from secondary origin to `/` (only when `follow-symlinks=yes`). Steps 6 and 7 swap when `symlink-priority=symlink-first`.
8. If `trust-env=yes` and `$AUTO_SHEBANG_FALLBACK_EXE` is set, validate and use it.
9. **Fail** with actionable error message listing search origins, probe-dirs, suffixes, and a debug hint.

### Candidate validation

A candidate is valid if it:

- Exists and is a regular file (`-f`), which also excludes dangling symlinks
- Is executable (`-x`)
- Is not the resolver itself, detected via `[ candidate -ef self ]` (inode comparison)

### Absolute probe-dir handling

Absolute and tilde-expanded probe-dirs entries don't depend on the walk directory. They are checked at their ordinal position on the first walk level only, then skipped on subsequent levels. This avoids redundant stat calls while preserving the author's intended search order.

### Path normalization

Uses `cd -P "$dir" && pwd -P` in a subshell. The `-P` flag resolves directory-level symlinks, so the walk origin is always a physical directory path. File-level symlinks are preserved — dual-origin search handles those separately. The subshell ensures the caller's working directory is not affected.

`readlink` is not used for normalization. It is only required for the opt-in `follow-symlinks` feature.

## Design decisions

| Decision | Rationale |
|---|---|
| Language-agnostic (busybox pattern) | One script, many languages via invocation name. |
| `#!/usr/bin/env /path/to/auto-python` | macOS needs binary shebang target. `env` is a universal trampoline. |
| PATH-based shebang as alternative only | PATH varies per user/shell/session. Not reliable for shared deployment. |
| POSIX sh, not bash | No bash features needed. Runs on dash, ash, busybox sh. |
| Default mode: pure POSIX sh, no external deps | `readlink` only needed for opt-in dual-origin. |
| Walk up the entire directory tree | Interpreter symlink may be at project root or any ancestor. |
| Intentional names (`auto-python`, not `python3`) | No `/bin/auto-python` exists. Safe to walk to root without false matches. |
| No `$PATH` fallback | Explicit failure is the correct behavior. Silent fallback hides bugs. |
| Dual-origin search (opt-in, requires readlink) | Find interpreters near both real file and symlink. Errors if readlink unavailable. |
| Real-first by default | Security: script author's interpreter wins over symlink deployer's context. |
| Parse directives before env vars | `trust-env` (a directive) controls whether env vars are read at all. |
| Directives are language-agnostic | Match `auto-shebang-<key>=<value>` anywhere in a line. No comment syntax needed. |
| Directive grammar: known keys only | Prevents accidental matches on `auto-shebang-` in string literals. |
| Directive value terminates at whitespace | Allows trailing comments. Values are paths/booleans — no spaces needed. |
| Boolean values: strict yes/no and 1/0 | No ambiguity. Invalid values are config errors, not silent defaults. |
| Env vars override directives (when trusted) | Runner controls their environment. defaults < directives < env vars. |
| `trust-env` directive, no env var counterpart | Untrusted env can't override its own distrust. Directive-only by design. |
| `trust-env=no` scope: `AUTO_SHEBANG_*` only | Shell inherently trusts `HOME`, `PATH`. We don't pretend otherwise. |
| `AUTO_SHEBANG_DEBUG` exempt from trust-env | Debug output doesn't affect resolution. Suppressing it helps no one. |
| OVERRIDE/FALLBACK validated like candidates | Prevents silent misbehavior from stale or misconfigured overrides. |
| Original invoked path passed to interpreter | Transparent proxy. Script sees same argv[0]/\_\_file\_\_ as without auto-shebang. |
| Normalization preserves caller's cwd | Subshell for cd -P. Resolver must not have side effects on the caller. |
| Self-detection via `[ -ef ]` | Inode comparison prevents infinite loops. Works in all practical shells. |
| Aliases: no flags, transparent proxy | Proxy must not consume interpreter arguments. Zero ambiguity. |
| `auto-shebang`: flags + explicit search name | Management interface on the real script, not aliases. |
| `--resolve` and `--check` safe against untrusted scripts | No code from inspected script is executed. |
| Library mode via env var guard | `AUTO_SHEBANG_LIB=1` — explicit, works everywhere. |
| Symlink cycle protection (40 hop limit) | Matches Linux SYMLOOP_MAX. Prevents infinite loops on malicious links. |
| Exit codes: 0/1/2/126/127 | Standard shell conventions. Distinguishes not-found from config error. |
| Safe `$VAR` substitution, not `eval` | `eval` is too broad. Safe expansion handles the useful cases without RCE risk. |
| `unsafe-expand-probe-dirs` naming | The "unsafe" prefix warns that values come from the environment. Default off. |

## Explicitly not included

| Feature | Why not |
|---|---|
| Stop markers (`.git`, etc.) | `auto-python` name prevents false matches. Walking to root is fast. |
| Caching | Stat calls are fast. Caching adds invalidation complexity for no measurable gain. |
| Version checking | Per-script concern. Scripts should check `sys.version_info` or equivalent. |
| `--list` (show all candidates) | `AUTO_SHEBANG_DEBUG=1` already shows the trace. Addable later if needed. |
| `readlink -f` | GNU-only. Single-level `readlink` in a loop when needed. |
| `readlink` as hard dependency | Only needed for opt-in dual-origin. Default mode is pure POSIX sh. |
| Shell `eval` for probe-dir expansion | Too broad: enables command substitution, backticks, globs. Safe `$VAR` substitution suffices. |
| Auto-privilege detection (euid != ruid) | Fragile, platform-specific. `trust-env=no` covers the use case explicitly. |
| World-writable symlink dir guard | Symlink walk is already opt-in. Document the risk, don't add the check. |
| Windows native | Shebangs don't work on native Windows. WSL and Git Bash work. |

## Dead ends

| Approach | Why abandoned |
|---|---|
| `#!/usr/bin/env python3` | PATH-based lookup is unreliable across environments. |
| Hardcoded shebangs (`#!/opt/.../python3`) | Machine-specific, non-portable, doesn't scale. |
| Symlink named `python3` | Collides with `/usr/bin/python3` when tree walk reaches `/usr/bin`. |
| `#!/path/to/auto-python` (no env) | Linux-only. macOS requires shebang targets to be compiled binaries. |
| Python-specific resolver | Algorithm is language-agnostic. Generalizing costs nothing. |
| Bash-only (`#!/bin/bash`) | No bash features needed. POSIX sh is more portable. |
| Shallow search (1-2 levels up) | Insufficient for real project layouts with deep nesting. |
| Symlink-first as default | Hostile symlink → hostile interpreter. Real-first is the secure default. |
| Follow-symlinks default yes | Adds `readlink` dependency for no benefit in the common case. |
| `ls -ld` fallback for readlink | Fragile: locale-dependent, escaping issues, ` -> ` parsing. |
| `eval` always-on for probe-dirs | RCE vector in check/resolve modes via malicious directives. |
| `eval` for probe-dirs (exec-mode only) | Semantic divergence: check/resolve would disagree with exec when variables are used. |
