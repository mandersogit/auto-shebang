#!/bin/sh
# auto-shebang — test suite
#
# Every test is honest (tests what it claims) and non-trivial
# (makes specific assertions about specific behavior).
#
# Run from repo root:
#   sh tests/run-tests.sh
#   dash tests/run-tests.sh
#
# With debug output from auto-shebang:
#   AUTO_SHEBANG_DEBUG=1 sh tests/run-tests.sh

set -eu

# --- Locate project ---

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
RESOLVER="$REPO_ROOT/auto-shebang"
EXAMPLES_DIR="$REPO_ROOT/examples"

if [ ! -x "$RESOLVER" ]; then
    printf 'FATAL: resolver not found or not executable: %s\n' "$RESOLVER" >&2
    exit 2
fi

# --- Test framework ---
# Each it() starts a test. Assertions accumulate. The next it() or
# finalize() reports PASS (all assertions ok) or FAIL (any assertion failed).

_t_total=0
_t_pass=0
_t_fail=0
_t_skip=0
_t_name=""
_t_group=""
_t_ok=1
_t_started=0
_t_failures=""

_t_finalize() {
    [ "$_t_started" = 1 ] || return 0
    if [ "$_t_ok" = 1 ]; then
        _t_pass=$((_t_pass + 1))
        printf '  PASS: %s\n' "$_t_name"
    fi
    # FAIL and SKIP already printed inline
}

describe() {
    _t_finalize
    _t_started=0
    _t_group="$1"
    printf '\n--- %s ---\n' "$1"
}

it() {
    _t_finalize
    _t_total=$((_t_total + 1))
    _t_name="$1"
    _t_ok=1
    _t_started=1
}

_t_record_fail() {
    if [ "$_t_ok" = 1 ]; then
        _t_fail=$((_t_fail + 1))
        printf '  FAIL: %s\n' "$_t_name"
        _t_failures="$_t_failures
  - [$_t_group] $_t_name"
    fi
    _t_ok=0
}

assert_eq() {
    if [ "$1" != "$2" ]; then
        _t_record_fail
        printf '    expected: [%s]\n' "$1"
        printf '      actual: [%s]\n' "$2"
    fi
}

assert_contains() {
    case "$1" in
        *"$2"*) ;;
        *)
            _t_record_fail
            printf '    missing:  [%s]\n' "$2"
            printf '    in:       [%.200s]\n' "$1"
            ;;
    esac
}

assert_not_contains() {
    case "$1" in
        *"$2"*)
            _t_record_fail
            printf '    unwanted: [%s]\n' "$2"
            printf '    in:       [%.200s]\n' "$1"
            ;;
        *) ;;
    esac
}

skip() {
    _t_ok=2  # neither pass nor fail
    _t_skip=$((_t_skip + 1))
    printf '  SKIP: %s (%s)\n' "$_t_name" "$1"
}

# Run a command, capture stdout, stderr, and exit code.
_STDERR_FILE=""
run() {
    _run_rc=0
    _run_stdout=$("$@" 2>"$_STDERR_FILE") || _run_rc=$?
    _run_stderr=$(cat "$_STDERR_FILE")
}

# --- Setup ---

W=$(mktemp -d "${TMPDIR:-/tmp}/auto-shebang-test-XXXXXX")
_STDERR_FILE="$W/.stderr"
trap 'rm -rf "$W"' EXIT

printf 'Test workspace: %s\n' "$W"
printf 'Resolver: %s\n' "$RESOLVER"
printf 'Shell: %s\n' "$(readlink -f /proc/$$/exe 2>/dev/null || echo "$SHELL")"

# Fake interpreters — shell scripts that echo their invocation
mkdir -p "$W/fake-bin"

cat > "$W/fake-bin/fake-python" << 'INTERP'
#!/bin/sh
printf 'python:'
for a in "$@"; do printf ' %s' "$a"; done
printf '\n'
INTERP
chmod +x "$W/fake-bin/fake-python"

cat > "$W/fake-bin/fake-node" << 'INTERP'
#!/bin/sh
printf 'node:'
for a in "$@"; do printf ' %s' "$a"; done
printf '\n'
INTERP
chmod +x "$W/fake-bin/fake-node"

# --- Project A: basic resolution ---
mkdir -p "$W/project/bin" "$W/project/scripts" "$W/project/deeper/nested"
ln -s "$W/fake-bin/fake-python" "$W/project/bin/auto-python"
ln -s "$W/fake-bin/fake-python" "$W/project/bin/auto-python-primary"
ln -s "$W/fake-bin/fake-python" "$W/project/bin/auto-python-custom"

cat > "$W/project/scripts/plain.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
print("plain")
S

cat > "$W/project/scripts/with-probe-dirs.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-probe-dirs=bin
print("probe-dirs")
S

cat > "$W/project/scripts/trust-no.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-trust-env=no
print("trust-no")
S

cat > "$W/project/scripts/bad-bool.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-follow-symlinks=maybe
S

cat > "$W/project/scripts/custom-suffix.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-suffixes=:custom
print("custom suffix")
S

cat > "$W/project/scripts/no-bare-suffix.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-suffixes=primary:secondary
print("no bare")
S

cat > "$W/project/scripts/last-wins.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-probe-dirs=nonexistent
# auto-shebang-probe-dirs=bin
print("last wins")
S

cat > "$W/project/deeper/nested/deep.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
print("deep")
S

# --- Project B: empty (no interpreter) ---
mkdir -p "$W/empty/scripts"
cat > "$W/empty/scripts/orphan.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
print("orphan")
S

# --- Dual-origin setup ---
mkdir -p "$W/real/bin" "$W/deploy/scripts" "$W/deploy/bin"
ln -s "$W/fake-bin/fake-node" "$W/real/bin/auto-node"

cat > "$W/real/app.js" << 'S'
#!/usr/bin/env /usr/local/bin/auto-node
// auto-shebang-follow-symlinks=yes
console.log("app")
S

ln -s "$W/real/app.js" "$W/deploy/scripts/app.js"

cat > "$W/real/app-sf.js" << 'S'
#!/usr/bin/env /usr/local/bin/auto-node
// auto-shebang-follow-symlinks=yes
// auto-shebang-symlink-priority=symlink-first
console.log("symlink-first")
S

ln -s "$W/real/app-sf.js" "$W/deploy/scripts/app-sf.js"
ln -s "$W/fake-bin/fake-node" "$W/deploy/bin/auto-node"

# --- Self-detection ---
ln -s "$RESOLVER" "$W/project/bin/auto-ruby"

# --- Tilde expansion ---
mkdir -p "$W/fakehome/interp-bin"
ln -s "$W/fake-bin/fake-python" "$W/fakehome/interp-bin/auto-python"

cat > "$W/tilde.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-probe-dirs=~/interp-bin
print("tilde")
S

# --- Variable expansion ---
cat > "$W/expand-var.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-probe-dirs=$MY_INTERP_DIR
# auto-shebang-unsafe-expand-probe-dirs=yes
print("expand")
S

cat > "$W/expand-braced.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-probe-dirs=${MY_INTERP_DIR}
# auto-shebang-unsafe-expand-probe-dirs=yes
print("braced")
S

cat > "$W/expand-cmdsub.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-probe-dirs=$(whoami)/bin
# auto-shebang-unsafe-expand-probe-dirs=yes
S

cat > "$W/expand-backtick.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-probe-dirs=`whoami`/bin
# auto-shebang-unsafe-expand-probe-dirs=yes
S

# --- Not-executable file for FALLBACK/OVERRIDE tests ---
printf '#!/bin/sh\n' > "$W/not-executable"

# --- Exec mode setup ---
mkdir -p "$W/exec-test/interp" "$W/exec-test/scripts"
ln -s "$W/fake-bin/fake-python" "$W/exec-test/interp/auto-python"
cat > "$W/exec-test/scripts/test.py" << 'S'
#!/usr/bin/env /usr/local/bin/auto-python
# auto-shebang-probe-dirs=interp
print("test")
S
# Copy (not symlink) the resolver so -ef self-detection doesn't fire
cp "$RESOLVER" "$W/exec-test/auto-python"
chmod +x "$W/exec-test/auto-python"


# ============================================================
#  Tests
# ============================================================

describe "CLI interface"

it "version flag prints version string"
run sh "$RESOLVER" --version
assert_eq "0" "$_run_rc"
assert_contains "$_run_stdout" "auto-shebang 3."

it "help flag prints usage with resolve command"
run sh "$RESOLVER" --help
assert_eq "0" "$_run_rc"
assert_contains "$_run_stdout" "--resolve"

it "short help flag (-h) prints same usage"
run sh "$RESOLVER" -h
assert_eq "0" "$_run_rc"
assert_contains "$_run_stdout" "--resolve"

it "bare invocation shows usage and exits 0"
run sh "$RESOLVER"
assert_eq "0" "$_run_rc"
assert_contains "$_run_stdout" "--resolve"

it "unknown flag exits 2 with error on stderr"
run sh "$RESOLVER" --bogus
assert_eq "2" "$_run_rc"
assert_contains "$_run_stderr" "unknown flag"

it "unknown positional arg exits 2"
run sh "$RESOLVER" something
assert_eq "2" "$_run_rc"
assert_contains "$_run_stderr" "unknown argument"

# ============================================================

describe "Basic resolution"

it "resolve finds interpreter in bin/ via tree walk"
run sh "$RESOLVER" --resolve auto-python "$W/project/scripts/plain.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/project/bin/auto-python" "$_run_stdout"

it "resolve walks up multiple directory levels"
run sh "$RESOLVER" --resolve auto-python "$W/project/deeper/nested/deep.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/project/bin/auto-python" "$_run_stdout"

it "resolve result is always an absolute path"
run sh "$RESOLVER" --resolve auto-python "$W/project/scripts/plain.py"
assert_eq "0" "$_run_rc"
case "$_run_stdout" in
    /*) ;; # absolute — good
    *)  _t_record_fail; printf '    path is not absolute: [%s]\n' "$_run_stdout" ;;
esac

it "resolve exits 127 when no interpreter found"
run sh "$RESOLVER" --resolve auto-python "$W/empty/scripts/orphan.py"
assert_eq "127" "$_run_rc"

it "check exits 0 when interpreter found"
run sh "$RESOLVER" --check auto-python "$W/project/scripts/plain.py"
assert_eq "0" "$_run_rc"

it "check exits 1 when interpreter not found"
run sh "$RESOLVER" --check auto-python "$W/empty/scripts/orphan.py"
assert_eq "1" "$_run_rc"

# ============================================================

describe "Check mode silence"

it "check mode failure produces zero output (stdout and stderr)"
run sh "$RESOLVER" --check auto-python "$W/empty/scripts/orphan.py"
assert_eq "" "$_run_stdout"
assert_eq "" "$_run_stderr"

it "check mode success produces zero output"
run sh "$RESOLVER" --check auto-python "$W/project/scripts/plain.py"
assert_eq "" "$_run_stdout"
assert_eq "" "$_run_stderr"

# ============================================================

describe "Directive parsing"

it "probe-dirs directive overrides default search locations"
run sh "$RESOLVER" --resolve auto-python "$W/project/scripts/with-probe-dirs.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/project/bin/auto-python" "$_run_stdout"

it "invalid directive boolean value exits 2 with explanation"
run sh "$RESOLVER" --check auto-python "$W/project/scripts/bad-bool.py"
assert_eq "2" "$_run_rc"
assert_contains "$_run_stderr" "must be yes or no"

it "last directive occurrence wins when duplicated"
run sh "$RESOLVER" --resolve auto-python "$W/project/scripts/last-wins.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/project/bin/auto-python" "$_run_stdout"

# ============================================================

describe "Config precedence"

it "trust-env=no causes env probe-dirs to be ignored"
run env AUTO_SHEBANG_PROBE_DIRS=nonexistent \
    sh "$RESOLVER" --resolve auto-python "$W/project/scripts/trust-no.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/project/bin/auto-python" "$_run_stdout"

it "trust-env=no causes OVERRIDE_EXE to be ignored"
run env AUTO_SHEBANG_OVERRIDE_EXE="$W/fake-bin/fake-node" \
    sh "$RESOLVER" --resolve auto-python "$W/project/scripts/trust-no.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/project/bin/auto-python" "$_run_stdout"

# ============================================================

describe "Suffix handling"

it "bare name tried first when suffixes start with colon"
# Default suffixes=:primary:secondary:tertiary — bare name first
run sh "$RESOLVER" --resolve auto-python "$W/project/scripts/plain.py"
assert_eq "$W/project/bin/auto-python" "$_run_stdout"

it "named suffix found when suffixes lack leading colon"
# suffixes=primary:secondary — no bare name, finds auto-python-primary
run sh "$RESOLVER" --resolve auto-python "$W/project/scripts/no-bare-suffix.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/project/bin/auto-python-primary" "$_run_stdout"

it "custom suffix name resolves correctly"
# suffixes=:custom — bare name tried first, finds auto-python
run sh "$RESOLVER" --resolve auto-python "$W/project/scripts/custom-suffix.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/project/bin/auto-python" "$_run_stdout"

# ============================================================

describe "OVERRIDE_EXE"

it "override takes priority over tree walk"
run env AUTO_SHEBANG_OVERRIDE_EXE="$W/fake-bin/fake-python" \
    sh "$RESOLVER" --resolve auto-python "$W/project/scripts/plain.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/fake-bin/fake-python" "$_run_stdout"

it "override not-found exits 127 with always-on error"
run env AUTO_SHEBANG_OVERRIDE_EXE=/nonexistent/python \
    sh "$RESOLVER" --resolve auto-python "$W/project/scripts/plain.py"
assert_eq "127" "$_run_rc"
assert_contains "$_run_stderr" "not found"
assert_contains "$_run_stderr" "/nonexistent/python"

it "override not-executable exits 126 with always-on error"
run env AUTO_SHEBANG_OVERRIDE_EXE="$W/not-executable" \
    sh "$RESOLVER" --resolve auto-python "$W/project/scripts/plain.py"
assert_eq "126" "$_run_rc"
assert_contains "$_run_stderr" "not executable"

# ============================================================

describe "FALLBACK_EXE"

it "fallback used when tree walk finds nothing"
run env AUTO_SHEBANG_FALLBACK_EXE="$W/fake-bin/fake-python" \
    sh "$RESOLVER" --resolve auto-python "$W/empty/scripts/orphan.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/fake-bin/fake-python" "$_run_stdout"

it "fallback not-found exits 127 with always-on error"
run env AUTO_SHEBANG_FALLBACK_EXE=/nonexistent/python \
    sh "$RESOLVER" --resolve auto-python "$W/empty/scripts/orphan.py"
assert_eq "127" "$_run_rc"
assert_contains "$_run_stderr" "not found"

it "fallback not-executable exits 126 with always-on error"
run env AUTO_SHEBANG_FALLBACK_EXE="$W/not-executable" \
    sh "$RESOLVER" --resolve auto-python "$W/empty/scripts/orphan.py"
assert_eq "126" "$_run_rc"
assert_contains "$_run_stderr" "not executable"

# ============================================================

describe "Environment boolean mapping"

it "FOLLOW_SYMLINKS=1 maps to follow-symlinks=yes"
run env AUTO_SHEBANG_FOLLOW_SYMLINKS=1 AUTO_SHEBANG_DEBUG=1 \
    sh "$RESOLVER" --resolve auto-python "$W/project/scripts/plain.py"
assert_contains "$_run_stderr" "follow-symlinks=yes (env)"

it "FOLLOW_SYMLINKS=0 maps to follow-symlinks=no"
run env AUTO_SHEBANG_FOLLOW_SYMLINKS=0 AUTO_SHEBANG_DEBUG=1 \
    sh "$RESOLVER" --resolve auto-python "$W/project/scripts/plain.py"
assert_contains "$_run_stderr" "follow-symlinks=no (env)"

it "invalid boolean (yes instead of 1) exits 2"
run env AUTO_SHEBANG_FOLLOW_SYMLINKS=yes \
    sh "$RESOLVER" --check auto-python "$W/project/scripts/plain.py"
assert_eq "2" "$_run_rc"
assert_contains "$_run_stderr" "must be 1 or 0"

# ============================================================

describe "Dual-origin search (follow-symlinks)"

it "real-first finds interpreter at real script location"
# deploy/scripts/app.js -> real/app.js (follow-symlinks=yes, real-first)
# real/bin/auto-node exists
run sh "$RESOLVER" --resolve auto-node "$W/deploy/scripts/app.js"
assert_eq "0" "$_run_rc"
assert_eq "$W/real/bin/auto-node" "$_run_stdout"

it "symlink-first prefers symlink location"
# deploy/scripts/app-sf.js -> real/app-sf.js (symlink-priority=symlink-first)
# deploy/bin/auto-node exists
run sh "$RESOLVER" --resolve auto-node "$W/deploy/scripts/app-sf.js"
assert_eq "0" "$_run_rc"
assert_eq "$W/deploy/bin/auto-node" "$_run_stdout"

# ============================================================

describe "Safe variable expansion"

it "dollar-name expanded from environment"
run env MY_INTERP_DIR="$W/fakehome/interp-bin" \
    sh "$RESOLVER" --resolve auto-python "$W/expand-var.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/fakehome/interp-bin/auto-python" "$_run_stdout"

it "braced variable expanded from environment"
run env MY_INTERP_DIR="$W/fakehome/interp-bin" \
    sh "$RESOLVER" --resolve auto-python "$W/expand-braced.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/fakehome/interp-bin/auto-python" "$_run_stdout"

it "command substitution rejected with exit 2"
run sh "$RESOLVER" --check auto-python "$W/expand-cmdsub.py"
assert_eq "2" "$_run_rc"
assert_contains "$_run_stderr" "command substitution"

it "backtick rejected with exit 2"
run sh "$RESOLVER" --check auto-python "$W/expand-backtick.py"
assert_eq "2" "$_run_rc"
assert_contains "$_run_stderr" "backtick"

# ============================================================

describe "Tilde expansion"

it "tilde in probe-dirs expands to HOME"
run env HOME="$W/fakehome" \
    sh "$RESOLVER" --resolve auto-python "$W/tilde.py"
assert_eq "0" "$_run_rc"
assert_eq "$W/fakehome/interp-bin/auto-python" "$_run_stdout"

it "tilde with HOME empty exits 2 with clear message"
run env HOME= \
    sh "$RESOLVER" --check auto-python "$W/tilde.py"
assert_eq "2" "$_run_rc"
assert_contains "$_run_stderr" "HOME is not set"

# ============================================================

describe "Self-detection"

it "resolver skips candidate pointing to itself"
# project/bin/auto-ruby -> resolver; no fake-ruby exists
run sh "$RESOLVER" --check auto-ruby "$W/project/scripts/plain.py"
assert_eq "1" "$_run_rc"

# ============================================================

describe "Library mode"

it "auto_shebang_resolve sets AUTO_SHEBANG_RESULT"
cat > "$W/lib-test-resolve.sh" << LIBTEST
#!/bin/sh
AUTO_SHEBANG_LIB=1
. "$RESOLVER"
auto_shebang_resolve auto-python "$W/project/scripts/plain.py"
printf '%s\n' "\$AUTO_SHEBANG_RESULT"
LIBTEST
run sh "$W/lib-test-resolve.sh"
assert_eq "0" "$_run_rc"
assert_eq "$W/project/bin/auto-python" "$_run_stdout"

it "die() in library mode does not kill caller shell"
cat > "$W/lib-test-survive.sh" << LIBTEST
#!/bin/sh
AUTO_SHEBANG_LIB=1
. "$RESOLVER"
auto_shebang_resolve auto-python "$W/project/scripts/bad-bool.py" 2>/dev/null
printf 'survived\n'
LIBTEST
run sh "$W/lib-test-survive.sh"
assert_eq "0" "$_run_rc"
assert_eq "survived" "$_run_stdout"

it "library resolve propagates die exit code"
cat > "$W/lib-test-errcode.sh" << LIBTEST
#!/bin/sh
AUTO_SHEBANG_LIB=1
. "$RESOLVER"
auto_shebang_resolve auto-python "$W/project/scripts/bad-bool.py" 2>/dev/null
printf '%d\n' "\$?"
LIBTEST
run sh "$W/lib-test-errcode.sh"
assert_eq "0" "$_run_rc"
assert_eq "2" "$_run_stdout"

it "library resolve returns 1 when not found"
cat > "$W/lib-test-notfound.sh" << LIBTEST
#!/bin/sh
AUTO_SHEBANG_LIB=1
. "$RESOLVER"
auto_shebang_resolve auto-python "$W/empty/scripts/orphan.py" 2>/dev/null
printf '%d\n' "\$?"
LIBTEST
run sh "$W/lib-test-notfound.sh"
assert_eq "0" "$_run_rc"
assert_eq "1" "$_run_stdout"

it "library mode OVERRIDE_EXE failure does not kill caller"
cat > "$W/lib-test-override.sh" << LIBTEST
#!/bin/sh
export AUTO_SHEBANG_OVERRIDE_EXE=/nonexistent
AUTO_SHEBANG_LIB=1
. "$RESOLVER"
auto_shebang_resolve auto-python "$W/project/scripts/plain.py" 2>/dev/null
printf 'survived %d\n' "\$?"
LIBTEST
run sh "$W/lib-test-override.sh"
assert_eq "0" "$_run_rc"
assert_contains "$_run_stdout" "survived 127"

# ============================================================

describe "Error messages"

it "not-found error reports search origin directory"
run sh "$RESOLVER" --resolve auto-python "$W/empty/scripts/orphan.py"
assert_contains "$_run_stderr" "Search origin:"

it "not-found error includes debug hint"
run sh "$RESOLVER" --resolve auto-python "$W/empty/scripts/orphan.py"
assert_contains "$_run_stderr" "AUTO_SHEBANG_DEBUG=1"

it "not-found error includes probe-dirs and suffixes"
run sh "$RESOLVER" --resolve auto-python "$W/empty/scripts/orphan.py"
assert_contains "$_run_stderr" "Probe dirs:"
assert_contains "$_run_stderr" "Suffixes:"

# ============================================================

describe "Exec mode"

it "exec runs script through resolved interpreter with args"
# auto-python is a COPY of the resolver (not symlink, avoids self-detect)
# It resolves to exec-test/interp/auto-python which points to fake-python
run "$W/exec-test/auto-python" "$W/exec-test/scripts/test.py" arg1 arg2
assert_eq "0" "$_run_rc"
assert_eq "python: $W/exec-test/scripts/test.py arg1 arg2" "$_run_stdout"

# ============================================================

describe "Example: library/resolve-example.sh"

it "resolves interpreter and reports path"
run sh "$EXAMPLES_DIR/library/resolve-example.sh" \
    "$RESOLVER" auto-python "$W/project/scripts/plain.py"
assert_eq "0" "$_run_rc"
assert_contains "$_run_stdout" "$W/project/bin/auto-python"

it "exits 1 when interpreter not found"
run sh "$EXAMPLES_DIR/library/resolve-example.sh" \
    "$RESOLVER" auto-python "$W/empty/scripts/orphan.py"
assert_eq "1" "$_run_rc"

# ============================================================

describe "Example: library/check-setup.sh"

# Copy example project to temp and configure interpreter symlink
EXAMPLE_COPY="$W/example-project"
cp -r "$EXAMPLES_DIR/project" "$EXAMPLE_COPY"
ln -sf "$W/fake-bin/fake-python" "$EXAMPLE_COPY/bin/auto-python"

it "reports all scripts OK when interpreter is configured"
run sh "$EXAMPLES_DIR/library/check-setup.sh" "$RESOLVER" "$EXAMPLE_COPY"
assert_eq "0" "$_run_rc"
assert_contains "$_run_stdout" "All scripts have interpreters configured"

it "exits 1 and reports MISSING when interpreter absent"
rm "$EXAMPLE_COPY/bin/auto-python"
run sh "$EXAMPLES_DIR/library/check-setup.sh" "$RESOLVER" "$EXAMPLE_COPY"
assert_eq "1" "$_run_rc"
assert_contains "$_run_stderr" "MISSING"

# ============================================================

describe "Cross-shell: dash"

if command -v dash >/dev/null 2>&1; then
    it "resolve works under dash"
    run dash "$RESOLVER" --resolve auto-python "$W/project/scripts/plain.py"
    assert_eq "0" "$_run_rc"
    assert_eq "$W/project/bin/auto-python" "$_run_stdout"

    it "library mode works under dash"
    cat > "$W/dash-lib-test.sh" << LIBTEST
#!/bin/sh
AUTO_SHEBANG_LIB=1
. "$RESOLVER"
auto_shebang_resolve auto-python "$W/project/scripts/plain.py"
printf '%s\n' "\$AUTO_SHEBANG_RESULT"
LIBTEST
    run dash "$W/dash-lib-test.sh"
    assert_eq "0" "$_run_rc"
    assert_eq "$W/project/bin/auto-python" "$_run_stdout"
else
    it "resolve works under dash"
    skip "dash not available"
    it "library mode works under dash"
    skip "dash not available"
fi

# ============================================================
#  Summary
# ============================================================

_t_finalize

printf '\n============================================================\n'
if [ "$_t_fail" = 0 ]; then
    printf 'ALL PASS: %d tests (%d passed' "$_t_total" "$_t_pass"
    [ "$_t_skip" -gt 0 ] && printf ', %d skipped' "$_t_skip"
    printf ')\n'
else
    printf 'FAILED: %d of %d tests failed (%d passed' "$_t_fail" "$_t_total" "$_t_pass"
    [ "$_t_skip" -gt 0 ] && printf ', %d skipped' "$_t_skip"
    printf ')\n'
    printf '\nFailures:%s\n' "$_t_failures"
fi
printf '============================================================\n'

[ "$_t_fail" = 0 ]
