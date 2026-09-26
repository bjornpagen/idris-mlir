"""tests/compiler: Core.Check unit tests and the frontend's artifact rules."""

from pathlib import Path
import os
import shutil

from harness import ROOT, artifacts, dev, run, stock_idris, text, workdir

HERE = Path(__file__).resolve().parent


def core_check():
    """CORE-CHECK-1: an Idris program runs Core.Check on invalid Core."""
    work = workdir("corecheck")
    os.symlink(ROOT / "compiler/src/IdrisMLIR", work / "IdrisMLIR")
    shutil.copy2(HERE / "CoreCheck.idr", work / "CoreCheck.idr")
    built = run([stock_idris(), "--no-banner", "--no-color", "-p", "contrib", "-o", "corecheck",
                 "CoreCheck.idr"], work, env=dev.idris_env())
    assert built.returncode == 0, text(built)
    ran = run([work / "build/exec/corecheck"], work)
    assert ran.returncode == 0, text(ran)
    shutil.rmtree(work, ignore_errors=True)


PROGRAM = """module Main

main : Int
main = 7
"""

UNSUPPORTED = """module Main

f : Int -> Int
f x = prim__shl_Int x 1

main : Int
main = f 7
"""


# rule: FE-ART-1, DRV-ART-1, FE-ENTRY-1, FE-ENTRY-2
def artifacts_follow_success():
    """Artifacts exist after success, are not rewritten when nothing changed,
    and are removed when the same module later fails."""
    work = workdir("artifacts")
    main = work / "Main.idr"
    main.write_text(PROGRAM)
    steps = dev.compile_int(main, work / "build/exec/Main")
    assert all(s.returncode == 0 for s in steps), "".join(text(s) for s in steps)
    files = artifacts(work, "Main.core") + artifacts(work, "Main.mlir")
    assert len(files) == 2, files
    before = [(f.read_bytes(), f.stat().st_mtime_ns) for f in files]
    steps = dev.compile_int(main, work / "build/exec/Main")
    assert [(f.read_bytes(), f.stat().st_mtime_ns) for f in files] == before, \
        "an unchanged module was compiled again"
    main.write_text(UNSUPPORTED)
    steps = dev.compile_int(main, work / "build/exec/Main")
    assert steps[0].returncode == 1, text(steps[0])
    assert not artifacts(work, "Main.core") and not artifacts(work, "Main.mlir"), \
        "stale artifacts survived a failure"
    shutil.rmtree(work, ignore_errors=True)


# rule: FE-ENTRY-5
def exec_is_rejected():
    work = workdir("exec")
    (work / "Main.idr").write_text("module Main\n\nimport IdrisMLIR.IO\n\nmain : IO ()\nmain = putStrLn \"x\"\n")
    compiler, _ = dev.built_tools()
    result = run([compiler, "--no-banner", "--no-color", "--no-prelude", "-p", "idris-mlir-io",
                  "--cg", "mlir", "--exec", "main", "Main.idr"], work, env=dev.idris_env())
    assert "unsupported (FE-ENTRY-5)" in text(result), text(result)
    shutil.rmtree(work, ignore_errors=True)


# rule: DRV-CC-1, DRV-CC-2, DIAG-ICE-1
def cc_rejects_contract_violations():
    """A contract violation is an internal error: exit 1, no output file."""
    work = workdir("cc")
    bad = work / "bad.mlir"
    bad.write_text('module attributes {idr.version = 0 : i64, idr.entry = @main, idr.entry_kind = "int"} {\n'
                   '  func.func private @main() -> i64 attributes {idr.name = "main"} {\n'
                   '    %0 = llvm.mlir.constant(1 : i64) : i64\n    return %0 : i64\n  }\n}\n')
    out = work / "bad.o"
    out.write_bytes(b"old")
    _, cc = dev.built_tools()
    result = run([cc, bad, "-o", out], work)
    assert result.returncode == 1, text(result)
    assert out.read_bytes() == b"old", "a failed compilation touched the existing output"
    usage = run([cc], work)
    assert usage.returncode == 2, text(usage)
    shutil.rmtree(work, ignore_errors=True)


def cases(filter_text=""):
    found = [("compiler/core-check", core_check),
             ("compiler/artifacts", artifacts_follow_success),
             ("compiler/exec", exec_is_rejected),
             ("compiler/cc-contract", cc_rejects_contract_violations)]
    return [(n, f) for n, f in found if filter_text in n]
