"""Run hand-written MLIR text through the pinned tools to a native executable."""

from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from native import build_executable  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixtures/exit_code.mlir"


def main():
    tools = Path(sys.argv[1])
    with tempfile.TemporaryDirectory(prefix="idris-mlir-pipeline-") as directory:
        work = Path(directory)
        exe = build_executable(tools, FIXTURE, work)
        lowered = (work / "lowered.mlir").read_text()
        assert "llvm.func @main" in lowered, lowered
        optimized = (work / "opt.ll").read_text()
        assert "ret i32 42" in optimized, optimized
        status = subprocess.run([exe]).returncode
        assert status == 42, f"executable exited {status}, expected 42"
        invalid = subprocess.run([tools / "mlir-opt"], input="module { invalid syntax }",
                                 capture_output=True, text=True)
        assert invalid.returncode != 0, "mlir-opt accepted invalid input"
    print("pinned MLIR tools produced a working executable")


if __name__ == "__main__":
    main()
