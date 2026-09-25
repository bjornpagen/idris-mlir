"""Run MLIR text through the pinned stock tools to a native executable."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

FIXTURE = Path(__file__).resolve().parent / "fixtures/exit_code.mlir"
EXPECTED_STATUS = 42


def step(args):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"{Path(args[0]).name} failed ({result.returncode}):\n{result.stderr}")
    return result


def main():
    tools = Path(sys.argv[1])
    for tool in ("mlir-opt", "mlir-translate", "opt", "llc"):
        if not (tools / tool).is_file():
            raise SystemExit(f"missing {tools / tool}")
    linker = shutil.which("cc")
    if linker is None:
        raise SystemExit("missing cc")
    with tempfile.TemporaryDirectory(prefix="idris-mlir-pipeline-") as directory:
        work = Path(directory)
        lowered, ir, optimized, obj, exe = (work / name for name in (
            "lowered.mlir", "out.ll", "opt.ll", "out.o", "out"))
        step([tools / "mlir-opt", FIXTURE, "--convert-to-llvm", "--reconcile-unrealized-casts",
              "-o", lowered])
        step([tools / "mlir-translate", "--mlir-to-llvmir", lowered, "-o", ir])
        step([tools / "opt", "-O2", "-S", ir, "-o", optimized])
        step([tools / "llc", "-O2", "-filetype=obj", "--relocation-model=pic", optimized, "-o", obj])
        step([linker, obj, "-o", exe])
        for artifact in (lowered, ir, optimized, obj, exe):
            if not artifact.is_file() or artifact.stat().st_size == 0:
                raise SystemExit(f"missing artifact {artifact.name}")
        if "llvm.func @main" not in lowered.read_text():
            raise SystemExit("mlir-opt did not lower func.func to llvm.func:\n" + lowered.read_text())
        if "ret i32 42" not in optimized.read_text():
            raise SystemExit("opt did not fold the arithmetic:\n" + optimized.read_text())
        status = subprocess.run([exe]).returncode
        if status != EXPECTED_STATUS:
            raise SystemExit(f"executable exited {status}, expected {EXPECTED_STATUS}")
        invalid = subprocess.run([tools / "mlir-opt"], input="module { invalid syntax }",
                                 capture_output=True, text=True)
        if invalid.returncode == 0:
            raise SystemExit("mlir-opt accepted invalid input")
    print("mlir-opt -> mlir-translate -> opt -> llc -> cc produced a working executable")


if __name__ == "__main__":
    main()
