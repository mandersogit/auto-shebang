#!/usr/bin/env /usr/local/bin/auto-python
"""Argument passing — shows that auto-shebang forwards all arguments.

Setup (one time):
    1. Install auto-shebang and create a language alias:
       ln -s /path/to/auto-shebang /usr/local/bin/auto-python

    2. Create an interpreter symlink in your project:
       ln -s "$(which python3)" bin/auto-python

Run with arguments:
    ./scripts/show-args.py one two three
"""

import sys

print(f"Script: {sys.argv[0]}")
for i, arg in enumerate(sys.argv[1:], 1):
    print(f"  arg {i}: {arg}")
