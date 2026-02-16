#!/usr/bin/env auto-python
"""Hello World — demonstrates auto-shebang interpreter resolution.

Setup (one time, from project root):
    ln -s "$(which python3)" bin/auto-python

Then run directly:
    ./scripts/hello.py
"""

print("Hello from auto-shebang!")
print("This script was run by whatever Python auto-shebang resolved.")
