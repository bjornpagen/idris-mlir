"""End-to-end fixtures (TEST-ORACLE-*, TEST-IO-1, TEST-DIFF-1, TEST-ELIM-1,
TEST-CRASH-1, TEST-HEAP-1, TEST-DET-1, TEST-EMIT-1).

tests/e2e/v0/<name>/ holds `Prog.idr`, a `main : Int` program, and one of:
  - `Oracle.idr`, with `check : Prog.main = <literal>` proved by `Refl`;
  - `expected-exit`, for results Idris cannot evaluate at type-checking time;
  - `expected-crash`, text the crash diagnostic must contain.
tests/e2e/v1/<name>/ and tests/e2e/v2/<name>/ hold `Main.idr` (and other user modules), optionally
`stdin`, `expected-stdout`, `expected-exit` (default 0), `expected-crash`,
an `Oracle.idr` checked with the stock compiler, `core.check`: FileCheck
directives run on the Core after Simplify, and `translate.check`: the same on
the full Core after Translate.
Either may hold `mlir.check`: FileCheck directives on the emitted contract.
"""

from pathlib import Path
import re
import shutil

from harness import (Skip, artifacts, assert_heap_free, copy_fixture, dev, llvm_tool,
                     run, stock_idris, text, workdir)
import e2e.sem as sem

HERE = Path(__file__).resolve().parent
V0_SYMBOLS = {"write", "_exit"}
V1_SYMBOLS = {"write", "read", "_exit"}
# LOW-EXT-1: v2 programs may also call these libm functions, including the
# ones LLVM substitutes for pow (SEM-DEV-2).
V2_SYMBOLS = V1_SYMBOLS | {"exp", "log", "pow", "sin", "cos", "tan", "asin", "acos", "atan",
                          "sqrt", "floor", "ceil", "exp2", "ldexp"}


def filecheck(checks, input_path):
    result = run([llvm_tool("FileCheck"), checks, f"--input-file={input_path}"], input_path.parent)
    assert result.returncode == 0, f"FileCheck {checks.name} on {input_path.name}:\n{text(result)}"


# rule: TEST-ORACLE-1, SEM-REF-1, SEM-LIT-1
def check_oracle(fixture, extra=()):
    """Stock Idris checks the Refl proof, so its evaluator agrees."""
    work = workdir("oracle")
    copy_fixture(fixture, work)
    result = run([stock_idris(), "--no-banner", "--no-color", "--no-prelude", *extra,
                  "--check", "Oracle.idr"], work, env=dev.idris_env())
    assert result.returncode == 0, f"stock idris2 rejects the oracle:\n{text(result)}"
    shutil.rmtree(work, ignore_errors=True)


def oracle_value(fixture):
    source = (fixture / "Oracle.idr").read_text()
    match = re.search(r"^check\s*:\s*Prog\.main\s*=\s*(-?\d+)\s*$", source, re.M)
    assert match, "Oracle.idr must contain `check : Prog.main = <integer literal>`"
    assert len(re.findall(r"^check\s*=\s*Refl\s*$", source, re.M)) == 1, "one `check = Refl`"
    return int(match.group(1))


def compile_v0(work):
    exe = work / "build/exec/Prog"
    steps = dev.compile_int(work / "Prog.idr", exe)
    assert len(steps) == 3 and all(s.returncode == 0 for s in steps), \
        "DRV-FLOW-1 failed:\n" + "".join(text(s) for s in steps)
    for pattern in ("Prog.core", "Prog.mlir"):
        assert artifacts(work, pattern), f"missing {pattern}"
    assert exe.with_suffix(".o").is_file() and exe.is_file(), "missing object or executable"
    return exe


# rule: TEST-CRASH-1, TEST-ORACLE-2, SEM-CRASH-1, SEM-PROG-1, DRV-FLOW-1, FE-ENTRY-2, CORE-DUMP-1
def v0_case(fixture):
    def case():
        if (fixture / "Oracle.idr").is_file():
            expected = oracle_value(fixture)
            check_oracle(fixture)
        else:
            expected = None
        work = workdir("e2e")
        copy_fixture(fixture, work)
        exe = compile_v0(work)
        result = run([exe], work, small_stack=True)
        if (fixture / "expected-crash").is_file():
            cause = (fixture / "expected-crash").read_text().strip()
            assert result.returncode == 1, f"a crash exits 1, got {result.returncode}"
            assert result.stdout == b"", f"stdout: {result.stdout!r}"
            assert cause.encode() in result.stderr, f"stderr {result.stderr!r} lacks {cause!r}"
        else:
            if expected is None:
                expected = int((fixture / "expected-exit").read_text().split()[0])
            assert result.returncode == expected % 256, \
                f"exit {result.returncode}, expected {expected} mod 256 = {expected % 256}"
            assert result.stdout == b"" and result.stderr == b"", \
                f"output: {result.stdout!r} {result.stderr!r}"
        assert_heap_free(exe.with_suffix(".o"), V0_SYMBOLS)
        if (fixture / "mlir.check").is_file():
            filecheck(fixture / "mlir.check", artifacts(work, "Prog.mlir")[0])
        shutil.rmtree(work, ignore_errors=True)
    return case


# rule: TEST-IO-1, TEST-DIFF-1, TEST-ELIM-1, SEM-DEV-1, DRV-FLOW-2, DRV-DUMP-1, FE-ENTRY-4
def v1_case(fixture):
    def case():
        stdin = (fixture / "stdin").read_bytes() if (fixture / "stdin").is_file() else b""
        # TEST-DIFF-1: a fixture marked oracle-chez has no expected-stdout; the
        # stock Chez backend's output is its only oracle.
        chez_only = (fixture / "oracle-chez").is_file()
        expected_out = (fixture / "expected-stdout").read_bytes() \
            if (fixture / "expected-stdout").is_file() else b""
        expected_exit = int((fixture / "expected-exit").read_text().split()[0]) \
            if (fixture / "expected-exit").is_file() else 0
        crash = (fixture / "expected-crash").read_text().strip() \
            if (fixture / "expected-crash").is_file() else None
        if (fixture / "Oracle.idr").is_file():
            check_oracle(fixture, ("-p", "idris-mlir-io"))
        work = workdir("e2e")
        copy_fixture(fixture, work)
        dumped = (fixture / "core.check").is_file() or (fixture / "translate.check").is_file()
        directives = ["dump-core"] if dumped else []
        # A fixture may use installed packages besides idris-mlir-io.
        packages = (fixture / "packages").read_text().split() if (fixture / "packages").is_file() else []
        result = dev.compile_io(work / "Main.idr", "prog", directives, packages)
        assert result.returncode == 0, f"DRV-FLOW-2 failed:\n{text(result)}"
        exe = work / "build/exec/prog"
        for artifact in ("prog.core", "prog.mlir", "prog.o", "prog"):
            assert (work / "build/exec" / artifact).is_file(), f"missing {artifact}"
        ran = run([exe], work, stdin=stdin, small_stack=True)
        if not chez_only:
            assert ran.stdout == expected_out, f"stdout {ran.stdout!r}, expected {expected_out!r}"
        if crash is None:
            assert ran.returncode == expected_exit, f"exit {ran.returncode}, expected {expected_exit}"
            assert ran.stderr == b"", f"stderr: {ran.stderr!r}"
        else:
            assert ran.returncode == 1, f"a crash exits 1, got {ran.returncode}"
            assert crash.encode() in ran.stderr, f"stderr {ran.stderr!r} lacks {crash!r}"
        assert_heap_free(work / "build/exec/prog.o",
                         V2_SYMBOLS if fixture.parent.name in ("v2", "v3") else V1_SYMBOLS)
        if (fixture / "core.check").is_file():
            filecheck(fixture / "core.check", work / "build/exec/prog.dump/02-simplify.core")
        if (fixture / "translate.check").is_file():
            filecheck(fixture / "translate.check", work / "build/exec/prog.dump/01-translate.core")
        if (fixture / "mlir.check").is_file():
            filecheck(fixture / "mlir.check", work / "build/exec/prog.mlir")
        # The stock Chez backend on the same program and input.
        chez = workdir("chez")
        copy_fixture(fixture, chez)
        built = run([stock_idris(), "--no-banner", "--no-color", "--no-prelude", "-p", "idris-mlir-io",
                     *[x for p in packages for x in ("-p", p)],
                     "--cg", "chez", "-o", "prog", "Main.idr"], chez, env=dev.idris_env())
        assert built.returncode == 0, f"stock Chez build failed:\n{text(built)}"
        reference = run([chez / "build/exec/prog"], chez, stdin=stdin)
        theirs = reference.stdout
        if crash is not None and theirs.startswith(ran.stdout):
            # SEM-DEV-1: Chez writes some crash messages to stdout.
            rest = theirs[len(ran.stdout):]
            if rest == b"" or rest.startswith(b"ERROR: "):
                theirs = ran.stdout
        if theirs != ran.stdout:
            ours, theirs = ran.stdout.splitlines(), reference.stdout.splitlines()
            first = next((i for i, (a, b) in enumerate(zip(ours, theirs)) if a != b),
                         min(len(ours), len(theirs)))
            raise AssertionError(f"Chez and this compiler differ at line {first + 1}: Chez "
                                 f"{theirs[first:first + 3]!r}, this compiler {ours[first:first + 3]!r}")
        if crash is None:
            assert reference.returncode == ran.returncode, \
                f"Chez exited {reference.returncode}, this compiler {ran.returncode}"
        shutil.rmtree(work, ignore_errors=True)
        shutil.rmtree(chez, ignore_errors=True)
    return case


# rule: TEST-DET-1, FE-DET-1, DRV-DET-1
def determinism_case(fixture, io):
    def case():
        work = workdir("det")
        copy_fixture(fixture, work)
        outputs = []
        for _ in range(2):
            shutil.rmtree(work / "build", ignore_errors=True)
            if io:
                result = dev.compile_io(work / "Main.idr", "prog")
                assert result.returncode == 0, text(result)
                files = [work / "build/exec" / n for n in ("prog.core", "prog.mlir", "prog.o", "prog")]
            else:
                compile_v0(work)
                files = artifacts(work, "Prog.core") + artifacts(work, "Prog.mlir") + \
                    [work / "build/exec/Prog.o", work / "build/exec/Prog"]
            outputs.append([f.read_bytes() for f in files])
        for (a, b, name) in zip(outputs[0], outputs[1], ("core", "mlir", "object", "executable")):
            assert a == b, f"the {name} differs between two compilations"
        shutil.rmtree(work, ignore_errors=True)
    return case


def cases(filter_text=""):
    found = []
    for fixture in sorted((HERE / "v0").glob("*/")):
        found.append((f"e2e/v0/{fixture.name}", v0_case(fixture)))
    for version in ("v1", "v2", "v3"):
        for fixture in sorted((HERE / version).glob("*/")):
            found.append((f"e2e/{version}/{fixture.name}", v1_case(fixture)))
    found.append(("e2e/v0/determinism", determinism_case(HERE / "v0/shapes", False)))
    found.append(("e2e/v1/determinism", determinism_case(HERE / "v1/hello", True)))
    found += sem.cases(v0_case)
    return [(name, fn) for name, fn in found if filter_text in name]


__all__ = ["cases", "Skip"]
