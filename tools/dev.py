#!/usr/bin/env python3
"""Local development entry point. Requires only Python's standard library."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / ".toolchain" / "idris2"


def run(args, cwd=ROOT, env=None, capture=False):
    return subprocess.run(
        [str(arg) for arg in args], cwd=cwd, env=env, check=True,
        text=True, capture_output=capture,
    )


def lock():
    data = json.loads((ROOT / "toolchain.lock.json").read_text())
    if data["schema_version"] != 1:
        raise ValueError("Unsupported toolchain lock schema")
    for name in ("idris2", "llvm"):
        if not re.fullmatch(r"[0-9a-f]{40}", data[name]["revision"]):
            raise ValueError(f"{name} must be pinned to a full Git commit")
    return data


def verify_pins():
    data = lock()
    dependency = ROOT / data["idris2"]["path"]
    if not (dependency / ".git").exists():
        raise ValueError("Initialize dependencies with git submodule update --init --recursive")
    actual = run(["git", "rev-parse", "HEAD"], cwd=dependency, capture=True).stdout.strip()
    expected = data["idris2"]["revision"]
    if actual != expected:
        raise ValueError(f"Idris checkout is {actual}; lock requires {expected}")
    entry = run(
        ["git", "ls-files", "--stage", "--", data["idris2"]["path"]], capture=True
    ).stdout.split()
    if len(entry) < 3 or entry[0] != "160000" or entry[1] != expected:
        raise ValueError("Staged/committed Idris submodule pin does not match the lock")
    dirty = run(
        ["git", "status", "--porcelain", "--untracked-files=no"],
        cwd=dependency, capture=True,
    ).stdout
    if dirty:
        raise ValueError("The Idris dependency has tracked modifications:\n" + dirty)
    package = (dependency / "idris2api.ipkg").read_text()
    version = re.search(r"^version\s*=\s*(\S+)", package, re.MULTILINE).group(1)
    binary = (dependency / "src/Core/Binary.idr").read_text()
    ttc = re.search(r"^ttcVersion\s*=\s*([0-9_]+)", binary, re.MULTILINE).group(1)
    if version != data["idris2"]["package_version"] or int(ttc.replace("_", "")) != data["idris2"]["ttc_version"]:
        raise ValueError("Pinned source package/TTC versions disagree with the lock")
    return data


def local_env():
    env = os.environ.copy()
    for key in ("IDRIS2_PATH", "IDRIS2_PACKAGE_PATH", "IDRIS2_INC_CGS",
                "IDRIS2_DATA", "IDRIS2_LIBS", "IDRIS2_CG", "IDRIS2_BOOT"):
        env.pop(key, None)
    env["IDRIS2_PREFIX"] = str(PREFIX)
    env["PATH"] = str(PREFIX / "bin") + os.pathsep + env.get("PATH", "")
    return env


def installed_env(data):
    compiler = PREFIX / "bin/idris2"
    stamp = PREFIX / "provenance.json"
    if not compiler.is_file() or not stamp.is_file():
        raise ValueError("Build the local compiler/API with bootstrap-idris first")
    provenance = json.loads(stamp.read_text())
    if provenance["idris2_revision"] != data["idris2"]["revision"]:
        raise ValueError("Local toolchain is stale; rebuild for the locked revision")
    env = local_env()
    env["CHEZ"] = provenance["scheme"]
    return compiler, env


def bootstrap(data, scheme):
    executable = shutil.which(scheme)
    if executable is None:
        raise ValueError(f"Chez Scheme executable not found: {scheme}")
    executable = str(Path(executable).resolve())
    for required in ("make", "cc", "git"):
        if shutil.which(required) is None:
            raise ValueError(f"Missing required tool: {required}")
    dependency = ROOT / data["idris2"]["path"]
    PREFIX.mkdir(parents=True, exist_ok=True)
    # A failed rebuild must not leave a success stamp for a partial install.
    (PREFIX / "provenance.json").unlink(missing_ok=True)
    env = local_env()
    # Upstream's bootstrap recursively changes PREFIX for its intermediate
    # installation. An inherited IDRIS2_PREFIX would override those defaults.
    env.pop("IDRIS2_PREFIX", None)
    env["CHEZ"] = executable
    options = [f"PREFIX={PREFIX}", f"SCHEME={executable}"]
    run(["make", "bootstrap", *options], cwd=dependency, env=env)
    run(["make", "install", *options], cwd=dependency, env=env)
    run(["make", "install-api", *options, f"IDRIS2_BOOT={PREFIX / 'bin/idris2'}"],
        cwd=dependency, env=env)
    (PREFIX / "provenance.json").write_text(json.dumps({
        "idris2_revision": data["idris2"]["revision"], "scheme": executable,
    }, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("doctor", "check", "verify-pins", "build-frontend", "test-frontend",
                 "build-mlir", "test-mlir"):
        commands.add_parser(name)
    boot = commands.add_parser("bootstrap-idris")
    boot.add_argument("--scheme", required=True, help="Threaded Chez Scheme executable")
    config = commands.add_parser("configure-mlir")
    config.add_argument("--mlir-dir", required=True, type=Path)
    args = parser.parse_args()
    data = verify_pins()
    if args.command == "verify-pins":
        print("Idris source, Git submodule, and toolchain lock agree")
    elif args.command == "doctor":
        print("Idris pin:", data["idris2"]["revision"])
        print("LLVM pin:", data["llvm"]["tag"], data["llvm"]["revision"])
        for tool in ("git", "make", "cc", "c++", "cmake", "ninja", "scheme", "chez", "chezscheme"):
            print(f"{tool}: {shutil.which(tool) or 'not found on PATH'}")
        print("Local Idris/API:", "built" if (PREFIX / "provenance.json").exists() else "not built")
        print("MLIR: supply --mlir-dir to configure-mlir; availability is not inferred")
    elif args.command == "check":
        run([sys.executable, "-m", "unittest", "discover", "-s", "tests/tooling", "-v"])
        print("Scaffold checks passed; frontend and MLIR integration tests are separate")
    elif args.command == "bootstrap-idris":
        bootstrap(data, args.scheme)
    elif args.command == "build-frontend":
        compiler, env = installed_env(data)
        run([compiler, "--build", "frontend.ipkg"], cwd=ROOT / "frontend", env=env)
    elif args.command == "test-frontend":
        _, env = installed_env(data)
        frontend = ROOT / "frontend/build/exec/idris-mlir"
        if not frontend.is_file():
            raise ValueError("Run build-frontend before test-frontend")
        run([sys.executable, "tests/frontend/check_inspector.py", frontend], env=env)
    elif args.command == "configure-mlir":
        mlir_dir = args.mlir_dir.resolve()
        if not (mlir_dir / "MLIRConfig.cmake").is_file():
            raise ValueError(f"MLIRConfig.cmake not found in {mlir_dir}")
        run(["cmake", "-S", ROOT, "-B", ROOT / "build/mlir", "-G", "Ninja",
             f"-DMLIR_DIR={mlir_dir}", "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_TESTING=ON"])
    elif args.command == "build-mlir":
        run(["cmake", "--build", ROOT / "build/mlir", "--target", "idris-mlir-opt"])
    elif args.command == "test-mlir":
        run(["ctest", "--test-dir", ROOT / "build/mlir", "--output-on-failure"])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, FileNotFoundError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
