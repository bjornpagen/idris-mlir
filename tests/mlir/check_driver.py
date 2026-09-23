"""Exercise real parsing, canonicalization, and rejection by our MLIR driver."""

import subprocess
import sys


def main():
    driver, fixture = sys.argv[1:]
    result = subprocess.run(
        [driver, fixture, "--canonicalize"], capture_output=True, text=True
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr)
    if "arith.constant 3 : i64" not in result.stdout or "arith.addi" in result.stdout:
        raise SystemExit("Constant addition was not folded:\n" + result.stdout)
    invalid = subprocess.run(
        [driver], input="module { invalid syntax }", capture_output=True, text=True
    )
    if invalid.returncode == 0:
        raise SystemExit("Invalid MLIR was accepted")
    print("MLIR parsing, canonicalization, and rejection passed")


if __name__ == "__main__":
    main()
