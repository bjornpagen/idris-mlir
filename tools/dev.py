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
LLVM_BUILD = TOOLCHAIN / "llvm-build-gcc"
LLVM_PREFIX = TOOLCHAIN / "llvm"
LLVM_TOOLS = ("mlir-opt", "mlir-translate", "mlir-tblgen", "opt", "llc", "llvm-nm",
              "FileCheck", "not", "count")
GCC_PREFIX = TOOLCHAIN / "gcc"
CMAKE_PREFIX = TOOLCHAIN / "cmake"
NINJA_PREFIX = TOOLCHAIN / "ninja"
COMPILER = ROOT / "compiler/build/exec/idris-mlir"
BUILD = ROOT / "build/dev"
IDRIS_MLIR_CC = BUILD / "foreign/idr/idris-mlir-cc"
IDRIS_MLIR_OPT = BUILD / "foreign/idr/idris-mlir-opt"
PATHS_MODULE = ROOT / "compiler/src/IdrisMLIR/Frontend/Paths.idr"
IO_PACKAGE = ROOT / "lib/idris-mlir-io/idris-mlir-io.ipkg"


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


def lock(name):
    data = json.loads((ROOT / "toolchain.lock.json").read_text())
    if data.get("schema_version") != 3:
        raise ValueError("Unsupported toolchain lock schema")
    return data[name]


def llvm_lock():
    return lock("llvm")


def clone_pinned(name, dest):
    """Shallow-clone the locked tag of `name` into `dest` and verify its commit."""
    entry = lock(name)
    if not (dest / ".git").exists():
        run(["git", "clone", "--depth", "1", "--branch", entry["tag"],
             entry["repository"], dest])
    head = git("rev-parse", "HEAD", cwd=dest)
    if head != entry["revision"]:
        raise ValueError(f"{dest} is at {head}; lock requires {entry['revision']}")
    return entry


def stamped(prefix, name):
    """The prefix of a pinned tool whose stamp matches the lock, or an error."""
    stamp = read_stamp(prefix)
    if stamp is None or stamp.get("revision") != lock(name)["revision"]:
        raise ValueError(f"Pinned {name} missing or stale; run: dev.py bootstrap-{name}")
    return prefix


def write_stamp(prefix, name, **extra):
    (prefix / "provenance.json").write_text(json.dumps(
        {"revision": lock(name)["revision"], **extra}, indent=2) + "\n")


def pinned_cc():
    return stamped(GCC_PREFIX, "gcc") / "bin/gcc"


def pinned_cxx():
    return stamped(GCC_PREFIX, "gcc") / "bin/g++"


def pinned_cmake():
    return stamped(CMAKE_PREFIX, "cmake") / "bin/cmake"


def pinned_ninja():
    return stamped(NINJA_PREFIX, "ninja") / "bin/ninja"


def bootstrap_gcc():
    require("git", "make", "cc", "c++", "flex")
    source, build = TOOLCHAIN / "gcc-src", TOOLCHAIN / "gcc-build"
    clone_pinned("gcc", source)
    GCC_PREFIX.mkdir(parents=True, exist_ok=True)
    (GCC_PREFIX / "provenance.json").unlink(missing_ok=True)
    shutil.rmtree(build, ignore_errors=True)
    build.mkdir(parents=True)
    # GMP, MPFR and MPC come from the distribution (TC-PIN-3).
    run([source / "configure", f"--prefix={GCC_PREFIX}", "--enable-languages=c,c++",
         "--disable-multilib", "--disable-bootstrap", "--disable-nls"], cwd=build)
    run(["make", f"-j{os.cpu_count() or 1}"], cwd=build)
    run(["make", "install"], cwd=build)
    write_stamp(GCC_PREFIX, "gcc")
    shutil.rmtree(build)


def bootstrap_cmake():
    require("git", "make", "c++")
    source = TOOLCHAIN / "cmake-src"
    clone_pinned("cmake", source)
    CMAKE_PREFIX.mkdir(parents=True, exist_ok=True)
    (CMAKE_PREFIX / "provenance.json").unlink(missing_ok=True)
    run(["./bootstrap", f"--prefix={CMAKE_PREFIX}", f"--parallel={os.cpu_count() or 1}",
         "--", "-DCMAKE_USE_OPENSSL=OFF", "-DBUILD_TESTING=OFF"], cwd=source)
    run(["make", f"-j{os.cpu_count() or 1}"], cwd=source)
    run(["make", "install"], cwd=source)
    write_stamp(CMAKE_PREFIX, "cmake")
    shutil.rmtree(source)


def bootstrap_ninja():
    require("git", "c++")
    source = TOOLCHAIN / "ninja-src"
    clone_pinned("ninja", source)
    (NINJA_PREFIX / "bin").mkdir(parents=True, exist_ok=True)
    (NINJA_PREFIX / "provenance.json").unlink(missing_ok=True)
    run([sys.executable, "configure.py", "--bootstrap"], cwd=source)
    shutil.copy2(source / "ninja", NINJA_PREFIX / "bin/ninja")
    write_stamp(NINJA_PREFIX, "ninja")
    shutil.rmtree(source)


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
    """TC-BOOT-2: LLVM/MLIR built with the pinned GCC, CMake and Ninja, installed
    into .toolchain/llvm with libraries, CMake packages and tools."""
    lock = llvm_lock()
    require("git")
    cc, cxx, cmake, ninja = pinned_cc(), pinned_cxx(), pinned_cmake(), pinned_ninja()
    LLVM_PREFIX.mkdir(parents=True, exist_ok=True)
    (LLVM_PREFIX / "provenance.json").unlink(missing_ok=True)
    clone_pinned("llvm", LLVM_SOURCE)
    run([cmake, "-S", LLVM_SOURCE / "llvm", "-B", LLVM_BUILD, "-G", "Ninja",
         f"-DCMAKE_MAKE_PROGRAM={ninja}",
         f"-DCMAKE_C_COMPILER={cc}",
         f"-DCMAKE_CXX_COMPILER={cxx}",
         f"-DCMAKE_INSTALL_PREFIX={LLVM_PREFIX}",
         # Everything built with the pinned GCC finds its libstdc++ (TC-BOOT-2).
         f"-DCMAKE_INSTALL_RPATH={GCC_PREFIX / 'lib64'}",
         f"-DCMAKE_BUILD_RPATH={GCC_PREFIX / 'lib64'}",
         "-DCMAKE_BUILD_TYPE=Release",
         "-DLLVM_ENABLE_PROJECTS=mlir",
         "-DLLVM_TARGETS_TO_BUILD=Native",
         "-DLLVM_ENABLE_ASSERTIONS=ON",
         "-DLLVM_ENABLE_RTTI=OFF",
         "-DLLVM_ENABLE_EH=OFF",
         "-DLLVM_INSTALL_UTILS=ON",
         "-DLLVM_BUILD_TOOLS=OFF",
         "-DLLVM_ENABLE_ZSTD=OFF",
         "-DLLVM_ENABLE_LIBXML2=OFF",
         "-DLLVM_INCLUDE_TESTS=OFF",
         "-DLLVM_INCLUDE_EXAMPLES=OFF",
         "-DLLVM_INCLUDE_BENCHMARKS=OFF",
         "-DLLVM_INCLUDE_DOCS=OFF",
         f"-DLLVM_PARALLEL_COMPILE_JOBS={compile_jobs()}",
         "-DLLVM_PARALLEL_LINK_JOBS=1"])
    # Tools outside `all` (LLVM_BUILD_TOOLS=OFF) are built and copied explicitly.
    run([cmake, "--build", LLVM_BUILD, "--target", *LLVM_TOOLS])
    run([cmake, "--build", LLVM_BUILD, "--target", "install"])
    (LLVM_PREFIX / "bin").mkdir(exist_ok=True)
    for tool in LLVM_TOOLS:
        target = LLVM_PREFIX / "bin" / tool
        if not target.exists():
            shutil.copy2(LLVM_BUILD / "bin" / tool, target)
    (LLVM_PREFIX / "provenance.json").write_text(json.dumps(
        {"llvm_revision": lock["revision"], "gcc_revision": lock_revision("gcc")},
        indent=2) + "\n")


def write_paths():
    """DRV-FLOW-2: the -o path runs the tools recorded here, never PATH."""
    text = (
        "||| Generated by tools/dev.py build: the pinned tools the -o path runs\n"
        "||| (DRV-FLOW-2). Do not edit.\n"
        "module IdrisMLIR.Frontend.Paths\n\n"
        "export\nidrisMlirCc : String\n"
        f"idrisMlirCc = {json.dumps(str(IDRIS_MLIR_CC))}\n\n"
        "export\npinnedCc : String\n"
        f"pinnedCc = {json.dumps(str(pinned_cc()))}\n")
    if not PATHS_MODULE.is_file() or PATHS_MODULE.read_text() != text:
        PATHS_MODULE.write_text(text)


def build():
    """TEST-CMD-1 `build`: the C++ dev preset, the Idris compiler, the IO package."""
    cmake = pinned_cmake()
    llvm_bin()
    run([cmake, "--preset", "dev"])
    run([cmake, "--build", "--preset", "dev"])
    env = idris_env()
    write_paths()
    run(["idris2", "--build", "idris-mlir.ipkg"], cwd=ROOT / "compiler", env=env)
    run(["idris2", "--install", IO_PACKAGE.name], cwd=IO_PACKAGE.parent, env=env)


def built_tools():
    """The tools `build` produces, or an error naming the command to run."""
    for path in (COMPILER, IDRIS_MLIR_CC, IDRIS_MLIR_OPT):
        if not path.is_file():
            raise ValueError(f"{path.relative_to(ROOT)} is missing; run: dev.py build")
    return COMPILER, IDRIS_MLIR_CC


def compile_int(source, output):
    """DRV-FLOW-1, the only copy of the chain for main : Int programs. Runs in
    the source's directory; returns the three completed processes."""
    source, output = Path(source).resolve(), Path(output).resolve()
    compiler, cc = built_tools()
    cwd = source.parent
    first = subprocess.run(
        [compiler, "--no-banner", "--no-color", "--no-prelude", "--cg", "mlir",
         "--inc", "mlir", "--check", source.name],
        cwd=cwd, env=idris_env(), capture_output=True, text=True)
    steps = [first]
    if first.returncode != 0:
        return steps
    found = sorted(cwd.glob(f"build/ttc/*/{source.stem}.mlir"))
    if not found and "No incremental compile data" in first.stdout + first.stderr:
        # PROF-PROG-1: Idris skips the incremental backend for a module that
        # imports one without `mlir` incremental data (the prelude package),
        # and exits 0 without writing anything. The chain reports it.
        import re
        lines = source.read_text().splitlines()
        line = next((i + 1 for i, text in enumerate(lines) if re.match(r"import\s", text)), 1)
        message = (f"Error: {source.stem}:{line}:1--{line}:1:mlir backend: {source.stem}: "
                   "unsupported (PROF-PROG-1): a main : Int program imports nothing\n")
        steps[0] = subprocess.CompletedProcess(first.args, 1, first.stdout, first.stderr + message)
        return steps
    if len(found) != 1:
        raise ValueError(f"expected one {source.stem}.mlir under build/ttc, found {found}")
    obj = output.with_suffix(".o")
    output.parent.mkdir(parents=True, exist_ok=True)
    steps.append(subprocess.run([cc, found[0], "-o", obj], capture_output=True, text=True))
    if steps[-1].returncode != 0:
        return steps
    steps.append(subprocess.run([pinned_cc(), obj, "-o", output, "-lm"],
                                capture_output=True, text=True))
    return steps


def compile_io(source, name, directives=(), packages=()):
    """DRV-FLOW-2: one command; the program lands in build/exec/<name> next to
    the source. Returns the completed process."""
    source = Path(source).resolve()
    compiler, _ = built_tools()
    args = [compiler, "--no-banner", "--no-color", "--no-prelude", "-p", "idris-mlir-io",
            "--cg", "mlir"]
    for package in packages:
        args += ["-p", package]
    for directive in directives:
        args += ["--directive", directive]
    return subprocess.run([*args, "-o", name, source.name], cwd=source.parent,
                          env=idris_env(), capture_output=True, text=True)


def is_io_program(source):
    import re
    return re.search(r"^main\s*:\s*IO\b", Path(source).read_text(), re.MULTILINE) is not None


def compile_command(source, output):
    source = Path(source)
    if is_io_program(source):
        result = compile_io(source, Path(output).name)
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        if result.returncode != 0:
            raise ValueError(f"compiling {source} failed")
        print(source.parent / "build/exec" / Path(output).name)
        return
    for step in compile_int(source, output):
        sys.stdout.write(step.stdout)
        sys.stderr.write(step.stderr)
        if step.returncode != 0:
            raise ValueError(f"compiling {source} failed")
    print(Path(output).resolve())


def lit_command():
    """The pinned LLVM's lit, from its source tree."""
    lit = LLVM_SOURCE / "llvm/utils/lit/lit.py"
    if not lit.is_file():
        raise ValueError("lit is missing; run: dev.py bootstrap-llvm")
    return [sys.executable, lit]


def test_idr():
    built_tools()
    tools = llvm_bin()
    for tool in ("FileCheck", "not", "count"):
        if not (tools / tool).is_file():
            raise ValueError(f"{tool} is missing from the pinned LLVM; run: dev.py bootstrap-llvm")
    env = os.environ.copy()
    env["PATH"] = os.pathsep.join([str(IDRIS_MLIR_OPT.parent), str(tools), env.get("PATH", "")])
    env["IDRIS_MLIR_PINNED_CC"] = str(pinned_cc())
    result = subprocess.run([*lit_command(), "-sv", ROOT / "tests/idr"], env=env)
    if result.returncode != 0:
        raise ValueError("test-idr failed")


def lock_revision(name):
    return lock(name)["revision"]


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
    llvm = llvm_lock()
    print("LLVM pin:", llvm["tag"], llvm["revision"])
    for tool in ("git", "make", "cc", "bash", "sha256sum",
                 "scheme", "chez", "chezscheme", "cmake", "ninja"):
        print(f"{tool}: {shutil.which(tool) or 'not found'}")
    print("GMP headers:", "found" if gmp_available() else "not found")
    stamp = read_stamp(IDRIS_PREFIX)
    print("Local Idris/API:", f"built at {stamp['idris2_revision']}" if stamp else "not built")
    for name, prefix in (("gcc", GCC_PREFIX), ("cmake", CMAKE_PREFIX), ("ninja", NINJA_PREFIX)):
        try:
            stamped(prefix, name)
            print(f"Pinned {name}: {lock(name)['version']}")
        except ValueError as error:
            print(f"Pinned {name}: {error}")
    for path in (COMPILER, IDRIS_MLIR_CC, IDRIS_MLIR_OPT):
        print(f"{path.relative_to(ROOT)}: {'built' if path.is_file() else 'not built (dev.py build)'}")
    stamp = read_stamp(LLVM_PREFIX)
    print("Local MLIR tools:", f"built at {stamp['llvm_revision']}" if stamp else "not built")
    for tool in LLVM_TOOLS if stamp else ():
        if tool in ("not", "count"):   # test utilities without --version
            present = (LLVM_PREFIX / "bin" / tool).is_file()
            print(f"  {tool}: {'present' if present else 'MISSING'}")
            continue
        output = run([LLVM_PREFIX / "bin" / tool, "--version"], capture=True).stdout
        ok = f"version {llvm['version']}" in output
        print(f"  {tool}: {'matches lock' if ok else 'VERSION MISMATCH'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("doctor", "check", "verify-pins", "bootstrap-gcc", "bootstrap-cmake",
                 "bootstrap-ninja", "bootstrap-llvm",
                 "build", "test-idr", "test-mlir-tools"):
        commands.add_parser(name)
    test = commands.add_parser("test")
    test.add_argument("filter", nargs="?", default="", help="Run only tests whose name contains this")
    comp = commands.add_parser("compile")
    comp.add_argument("source")
    comp.add_argument("-o", dest="output", required=True)
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
    elif args.command == "bootstrap-gcc":
        bootstrap_gcc()
    elif args.command == "bootstrap-cmake":
        bootstrap_cmake()
    elif args.command == "bootstrap-ninja":
        bootstrap_ninja()
    elif args.command == "bootstrap-llvm":
        bootstrap_llvm()
    elif args.command == "build":
        build()
    elif args.command == "compile":
        compile_command(args.source, args.output)
    elif args.command == "test":
        built_tools()
        run([sys.executable, "tests/run.py", args.filter])
    elif args.command == "test-idr":
        test_idr()
    elif args.command == "test-mlir-tools":
        run([sys.executable, "tests/mlir/check_pipeline.py", llvm_bin(), pinned_cc()])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, FileNotFoundError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
