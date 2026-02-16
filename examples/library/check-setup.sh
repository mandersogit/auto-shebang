#!/bin/sh
# Library mode example: validate that all scripts in a project can resolve.
#
# Useful as a CI step or post-clone hook to verify interpreter symlinks
# are correctly configured before running anything.
#
# Usage:
#   sh examples/library/check-setup.sh <auto-shebang> <project-dir>
#
# Example:
#   sh examples/library/check-setup.sh ./auto-shebang examples/project

set -eu

RESOLVER="${1:?Usage: $0 <path-to-auto-shebang> <project-dir>}"
PROJECT="${2:?}"

# Source auto-shebang in library mode
AUTO_SHEBANG_LIB=1
. "$RESOLVER"

errors=0
checked=0

for script in "$PROJECT"/scripts/*.py; do
    [ -f "$script" ] || continue
    checked=$((checked + 1))

    if auto_shebang_resolve auto-python "$script" 2>/dev/null; then
        printf 'OK:      %-30s → %s\n' "$(basename "$script")" "$AUTO_SHEBANG_RESULT"
    else
        printf 'MISSING: %-30s — no auto-python found\n' "$(basename "$script")" >&2
        errors=$((errors + 1))
    fi
done

printf '\nChecked %d script(s).\n' "$checked"

if [ "$errors" -gt 0 ]; then
    printf '%d script(s) have no interpreter configured.\n' "$errors" >&2
    printf 'Fix: ln -s /path/to/python3 %s/bin/auto-python\n' "$PROJECT" >&2
    exit 1
fi

printf 'All scripts have interpreters configured.\n'
