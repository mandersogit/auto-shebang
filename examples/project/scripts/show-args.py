#!/usr/bin/env auto-python
"""Argument passing — shows that auto-shebang forwards all arguments.

Setup (one time, from project root):
    ln -s "$(which python3)" bin/auto-python

Run with arguments:
    ./scripts/show-args.py one two three
"""

import sys

print(f"Script: {sys.argv[0]}")
for i, arg in enumerate(sys.argv[1:], 1):
    print(f"  arg {i}: {arg}")
