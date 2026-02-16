#!/bin/sh
# Library mode example: resolve an interpreter path without exec.
#
# auto-shebang can be sourced as a library. This lets build scripts,
# CI pipelines, and wrapper tools find interpreters programmatically
# without executing anything.
#
# Usage:
#   sh examples/library/resolve-example.sh <auto-shebang> <name> <script>
#
# Example:
#   sh examples/library/resolve-example.sh ./auto-shebang auto-python examples/project/scripts/hello.py

set -eu

RESOLVER="${1:?Usage: $0 <path-to-auto-shebang> <interpreter-name> <script-path>}"
NAME="${2:?}"
SCRIPT="${3:?}"

# Source auto-shebang in library mode (suppresses auto_shebang_main)
AUTO_SHEBANG_LIB=1
. "$RESOLVER"

# Resolve the interpreter — sets AUTO_SHEBANG_RESULT on success
if auto_shebang_resolve "$NAME" "$SCRIPT"; then
    printf 'Resolved %s for %s:\n' "$NAME" "$SCRIPT"
    printf '  %s\n' "$AUTO_SHEBANG_RESULT"

    # You could now use the resolved path however you need:
    #   "$AUTO_SHEBANG_RESULT" "$SCRIPT" "$@"   # run the script
    #   echo "$AUTO_SHEBANG_RESULT"              # report to CI
    #   export PYTHON="$AUTO_SHEBANG_RESULT"     # set for downstream
else
    printf 'Could not resolve %s for %s (exit %d)\n' "$NAME" "$SCRIPT" "$?" >&2
    exit 1
fi
