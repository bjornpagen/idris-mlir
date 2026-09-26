#!/usr/bin/env python3
"""Development entry point for idris-mlir. Standard library only."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
IDRIS_SOURCE = ROOT / "third_party/Idris2"
TOOLCHAIN = ROOT / ".toolchain"
IDRIS_PREFIX = TOOLCHAIN / "idris2"
LLVM_SOURCE = TOOLCHAIN / "llvm-project"
LLVM_BUILD = TOOLCHAIN / "llvm-build"
LLVM_PREFIX = TOOLCHAIN / "llvm"
LLVM_TOOLS = ("mlir-opt", "mlir-translate", "opt", "llc")
COMPILER = ROOT / "compiler/build/exec/idris-mlir"


def run(args, cwd=ROOT, env=None, capture=False):
    return subprocess.run(
        [str(arg) for arg in args], cwd=cwd, env=env, check=True,
        text=True, capture_output=capture,
    )


def git(*args, cwd=ROOT):
    return run(["git", *args], cwd=cwd, capture=True).stdout.strip()


def require(*tools):
    for tool in tools:
        if shutil.which(tool) is None:
            raise ValueError(f"Missing required tool: {tool}")


def llvm_lock():
    data = json.loads((ROOT / "toolchain.lock.json").read_text())
    if data.get("schema_version") != 2:
        raise ValueError("Unsupported toolchain lock schema")
    return data["llvm"]


def verify_idris_source():
    """The submodule must be checked out at its staged gitlink, unmodified."""
    if not (IDRIS_SOURCE / ".git").exists():
        raise ValueError("Idris source missing; run: git submodule update --init")
    entry = git("ls-files", "--stage", "--", "third_party/Idris2").split()
    if len(entry) < 2 or entry[0] != "160000":
        raise ValueError("third_party/Idris2 is not a submodule entry")
    head = git("rev-parse", "HEAD", cwd=IDRIS_SOURCE)
    if head != entry[1]:
        raise ValueError(f"Idris checkout is {head}; the staged pin is {entry[1]}")
    if git("status", "--porcelain", "--untracked-files=no", cwd=IDRIS_SOURCE):
        raise ValueError("third_party/Idris2 has tracked modifications")
    return head


def read_stamp(prefix):
    stamp = prefix / "provenance.json"
    return json.loads(stamp.read_text()) if stamp.is_file() else None


def local_env():
    env = os.environ.copy()
    for key in ("IDRIS2_PATH", "IDRIS2_PACKAGE_PATH", "IDRIS2_INC_CGS",
                "IDRIS2_DATA", "IDRIS2_LIBS", "IDRIS2_CG", "IDRIS2_BOOT"):
        env.pop(key, None)
    env["IDRIS2_PREFIX"] = str(IDRIS_PREFIX)
    env["PATH"] = str(IDRIS_PREFIX / "bin") + os.pathsep + env.get("PATH", "")
    return env


def idris_env():
    stamp = read_stamp(IDRIS_PREFIX)
    if stamp is None or not (IDRIS_PREFIX / "bin/idris2").is_file():
        raise ValueError("Build the local compiler/API with bootstrap-idris first")
    if stamp["idris2_revision"] != verify_idris_source():
        raise ValueError("Local Idris toolchain is stale; rerun bootstrap-idris")
    env = local_env()
    env["CHEZ"] = stamp["scheme"]
    return env


def llvm_bin():
    stamp = read_stamp(LLVM_PREFIX)
    if stamp is None:
        raise ValueError("Build the pinned MLIR tools with bootstrap-llvm first")
    if stamp["llvm_revision"] != llvm_lock()["revision"]:
        raise ValueError("Local LLVM tools are stale; rerun bootstrap-llvm")
    return LLVM_PREFIX / "bin"


def bootstrap_idris(scheme):
    executable = shutil.which(scheme)
    if executable is None:
        raise ValueError(f"Chez Scheme executable not found: {scheme}")
    executable = str(Path(executable).resolve())
    require("make", "cc", "git")
    revision = verify_idris_source()
    IDRIS_PREFIX.mkdir(parents=True, exist_ok=True)
    # A failed rebuild must not leave a success stamp for a partial install.
    (IDRIS_PREFIX / "provenance.json").unlink(missing_ok=True)
    env = local_env()
    # Upstream's bootstrap changes PREFIX for its intermediate installation;
    # an inherited IDRIS2_PREFIX would override that.
    env.pop("IDRIS2_PREFIX", None)
    env["CHEZ"] = executable
    options = [f"PREFIX={IDRIS_PREFIX}", f"SCHEME={executable}"]
    run(["make", "bootstrap", *options], cwd=IDRIS_SOURCE, env=env)
    run(["make", "install", *options], cwd=IDRIS_SOURCE, env=env)
    run(["make", "install-api", *options, f"IDRIS2_BOOT={IDRIS_PREFIX / 'bin/idris2'}"],
        cwd=IDRIS_SOURCE, env=env)
    (IDRIS_PREFIX / "provenance.json").write_text(json.dumps(
        {"idris2_revision": revision, "scheme": executable}, indent=2) + "\n")


def compile_jobs():
    """Parallel C++ compiles that fit in memory: some MLIR files need ~5 GB each."""
    memory = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
    return max(1, min(os.cpu_count() or 1, memory // (7 * 2**30)))


def bootstrap_llvm():
    lock = llvm_lock()
    require("git", "cmake", "ninja", "c++")
    LLVM_PREFIX.mkdir(parents=True, exist_ok=True)
    (LLVM_PREFIX / "provenance.json").unlink(missing_ok=True)
    if not (LLVM_SOURCE / ".git").exists():
        run(["git", "clone", "--depth", "1", "--branch", lock["tag"],
             lock["repository"], LLVM_SOURCE])
    head = git("rev-parse", "HEAD", cwd=LLVM_SOURCE)
    if head != lock["revision"]:
        raise ValueError(f"{LLVM_SOURCE} is at {head}; lock requires {lock['revision']}")
    run(["cmake", "-S", LLVM_SOURCE / "llvm", "-B", LLVM_BUILD, "-G", "Ninja",
         "-DCMAKE_BUILD_TYPE=Release",
         "-DLLVM_ENABLE_PROJECTS=mlir",
         "-DLLVM_TARGETS_TO_BUILD=Native",
         "-DLLVM_ENABLE_ASSERTIONS=ON",
         "-DLLVM_INCLUDE_TESTS=OFF",
         "-DLLVM_INCLUDE_EXAMPLES=OFF",
         "-DLLVM_INCLUDE_BENCHMARKS=OFF",
         f"-DLLVM_PARALLEL_COMPILE_JOBS={compile_jobs()}",
         "-DLLVM_PARALLEL_LINK_JOBS=1"])
    run(["cmake", "--build", LLVM_BUILD, "--target", *LLVM_TOOLS])
    (LLVM_PREFIX / "bin").mkdir(exist_ok=True)
    for tool in LLVM_TOOLS:
        shutil.copy2(LLVM_BUILD / "bin" / tool, LLVM_PREFIX / "bin" / tool)
    (LLVM_PREFIX / "provenance.json").write_text(json.dumps(
        {"llvm_revision": lock["revision"]}, indent=2) + "\n")


def gmp_available():
    probe = subprocess.run(
        ["cc", "-E", "-x", "c", "-", *os.environ.get("CPPFLAGS", "").split()],
        input="#include <gmp.h>\n", capture_output=True, text=True,
    ) if shutil.which("cc") else None
    return probe is not None and probe.returncode == 0


def doctor():
    try:
        print("Idris source:", verify_idris_source())
    except ValueError as error:
        print("Idris source: problem:", error)
    lock = llvm_lock()
    print("LLVM pin:", lock["tag"], lock["revision"])
    for tool in ("git", "make", "cc", "bash", "sha256sum",
                 "scheme", "chez", "chezscheme", "cmake", "ninja"):
        print(f"{tool}: {shutil.which(tool) or 'not found'}")
    print("GMP headers:", "found" if gmp_available() else "not found")
    stamp = read_stamp(IDRIS_PREFIX)
    print("Local Idris/API:", f"built at {stamp['idris2_revision']}" if stamp else "not built")
    stamp = read_stamp(LLVM_PREFIX)
    print("Local MLIR tools:", f"built at {stamp['llvm_revision']}" if stamp else "not built")
    for tool in LLVM_TOOLS if stamp else ():
        output = run([LLVM_PREFIX / "bin" / tool, "--version"], capture=True).stdout
        ok = f"version {lock['version']}" in output
        print(f"  {tool}: {'matches lock' if ok else 'VERSION MISMATCH'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("doctor", "check", "verify-pins", "bootstrap-llvm",
                 "build", "test", "test-mlir-tools"):
        commands.add_parser(name)
    boot = commands.add_parser("bootstrap-idris")
    boot.add_argument("--scheme", required=True, help="Threaded Chez Scheme executable")
    args = parser.parse_args()

    if args.command == "doctor":
        doctor()
    elif args.command == "verify-pins":
        print("Idris source matches its pin:", verify_idris_source())
    elif args.command == "check":
        run([sys.executable, "-m", "unittest", "discover", "-s", "tests/tooling", "-v"])
    elif args.command == "bootstrap-idris":
        bootstrap_idris(args.scheme)
    elif args.command == "bootstrap-llvm":
        bootstrap_llvm()
    elif args.command == "build":
        run(["idris2", "--build", "idris-mlir.ipkg"], cwd=ROOT / "compiler", env=idris_env())
    elif args.command == "test":
        env = idris_env()
        if not COMPILER.is_file():
            raise ValueError("Run build before test")
        run([sys.executable, "tests/compiler/check_compile.py", COMPILER, llvm_bin()], env=env)
    elif args.command == "test-mlir-tools":
        run([sys.executable, "tests/mlir/check_pipeline.py", llvm_bin()])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, FileNotFoundError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
