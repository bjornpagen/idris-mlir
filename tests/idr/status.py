"""Runs a command and succeeds only if it exits with the given status.
lit's internal shell has no `$?`; `%status N cmd...` checks exact statuses."""
import subprocess
import sys

expected, command = int(sys.argv[1]), sys.argv[2:]
status = subprocess.run(command).returncode
if status != expected:
    sys.exit(f"{command[0]} exited {status}, expected {expected}")
