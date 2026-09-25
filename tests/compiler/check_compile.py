"""End to end: Idris source -> idris-mlir -> MLIR text -> pinned tools -> executable."""

from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from native import build_executable  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def compile_module(compiler, work, source, success=True):
    result = subprocess.run(
        [compiler, "--no-banner", "--no-color", "--no-prelude",
         "--cg", "mlir", "--inc", "mlir", "--check", source],
        cwd=work, capture_output=True, text=True,
    )
    if (result.returncode == 0) != success:
        raise AssertionError(f"Unexpected status {result.returncode}:\n{result.stdout}\n{result.stderr}")
    return result.stdout + result.stderr


def artifacts(work, name):
    return list(work.glob(f"build/ttc/**/{name}"))


def only(work, name):
    found = artifacts(work, name)
    assert len(found) == 1, f"expected one {name}, found {found}"
    return found[0]


def main():
    compiler = str(Path(sys.argv[1]).resolve())
    tools = Path(sys.argv[2]).resolve()
    with tempfile.TemporaryDirectory(prefix="idris-mlir-test-") as directory:
        work = Path(directory)
        for fixture in FIXTURES.glob("*.idr"):
            shutil.copy2(fixture, work / fixture.name)

        compile_module(compiler, work, "Arith.idr")
        ir, mlir = only(work, "Arith.ir"), only(work, "Arith.mlir")
        ir_text, mlir_text = ir.read_text(), mlir.read_text()
        assert re.search(r"^fn Arith\.keep \(0 %\d+ : Int\) \(w %\d+ : Int\) : Int", ir_text, re.M), ir_text
        assert re.search(r"func\.func @Arith\.keep\(%a\d+: i64\) -> i64", mlir_text), mlir_text
        assert "arith.cmpi ult" in mlir_text, mlir_text

        exe = build_executable(tools, mlir, work / "native")
        status = subprocess.run([exe]).returncode
        assert status == 52, f"executable exited {status}, expected 52"

        before = [(path.read_bytes(), path.stat().st_mtime_ns) for path in (ir, mlir)]
        compile_module(compiler, work, "Arith.idr")
        after = [(path.read_bytes(), path.stat().st_mtime_ns) for path in (ir, mlir)]
        assert before == after, "an unchanged module was recompiled"

        compile_module(compiler, work, "BadErase.idr", success=False)
        assert not artifacts(work, "BadErase.mlir"), "a module that failed to check produced MLIR"

        output = compile_module(compiler, work, "Vectors.idr", success=False)
        assert "mlir backend" in output and "unsupported" in output, output
        assert not artifacts(work, "Vectors.mlir"), "an unsupported module produced MLIR"
    print("compiled Arith.idr to a native executable; erasure, cache, and rejection checks passed")


if __name__ == "__main__":
    main()
