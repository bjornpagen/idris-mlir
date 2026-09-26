"""`dev.py test`: tests/compiler, tests/profile and tests/e2e (TEST-CMD-1)."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import Results, run_cases  # noqa: E402
import compiler.suite  # noqa: E402
import e2e.suite  # noqa: E402
import profile.suite  # noqa: E402


def main():
    filter_text = sys.argv[1] if len(sys.argv) > 1 else ""
    results = Results()
    cases = compiler.suite.cases(filter_text) + profile.suite.cases(filter_text) + e2e.suite.cases(filter_text)
    run_cases(results, cases)
    print(results.summary())
    sys.exit(1 if results.failed else 0)


if __name__ == "__main__":
    main()
