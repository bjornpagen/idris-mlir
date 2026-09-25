"""The pinned MLIR-to-executable pipeline, shared by the tests."""

from pathlib import Path
import shutil
import subprocess

TOOLS = ("mlir-opt", "mlir-translate", "opt", "llc")
LOWERING = ("--convert-scf-to-cf", "--convert-to-llvm", "--reconcile-unrealized-casts")


def step(args):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError(f"{Path(args[0]).name} failed ({result.returncode}):\n{result.stderr}")


def build_executable(tools, source, work):
    """Lower MLIR text at `source` to an executable in `work`; return its path."""
    tools, work = Path(tools), Path(work)
    for tool in TOOLS:
        if not (tools / tool).is_file():
            raise AssertionError(f"missing {tools / tool}; run tools/dev.py bootstrap-llvm")
    linker = shutil.which("cc")
    if linker is None:
        raise AssertionError("missing cc")
    work.mkdir(parents=True, exist_ok=True)
    lowered, ir, optimized, obj, exe = (work / name for name in (
        "lowered.mlir", "out.ll", "opt.ll", "out.o", "out"))
    step([tools / "mlir-opt", source, *LOWERING, "-o", lowered])
    step([tools / "mlir-translate", "--mlir-to-llvmir", lowered, "-o", ir])
    step([tools / "opt", "-O2", "-S", ir, "-o", optimized])
    step([tools / "llc", "-O2", "-filetype=obj", "--relocation-model=pic", optimized, "-o", obj])
    step([linker, obj, "-o", exe])
    for artifact in (lowered, ir, optimized, obj, exe):
        if not artifact.is_file() or artifact.stat().st_size == 0:
            raise AssertionError(f"missing artifact {artifact}")
    return exe
