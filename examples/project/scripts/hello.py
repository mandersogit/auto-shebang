#!/usr/bin/env /usr/local/bin/auto-python
"""Hello World — demonstrates auto-shebang interpreter resolution.

Setup (one time):
    1. Install auto-shebang and create a language alias:
       ln -s /path/to/auto-shebang /usr/local/bin/auto-python

    2. Create an interpreter symlink in your project:
       ln -s "$(which python3)" bin/auto-python

    Then run directly:
       ./scripts/hello.py

The shebang above uses an absolute path to auto-python via /usr/bin/env.
This avoids any $PATH dependency — auto-shebang's whole purpose.
Adjust the path to wherever you installed the auto-python alias.
"""

print("Hello from auto-shebang!")
print("This script was run by whatever Python auto-shebang resolved.")
