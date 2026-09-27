#!/usr/bin/env python3
"""Runs the benchmarks: each program built by this compiler, by the stock
Idris Chez backend (the same source), by MLton (bench/sml) and by gcc -O2
(bench/c), on the same input. Prints a Markdown table of the best of
several wall-clock times, and checks that the outputs agree.

    python3 bench/run.py [--runs N] [name ...]

MLton is looked up in .toolchain/mlton (the Debian package, unpacked there
with dpkg -x) and then on PATH; a missing compiler is reported and skipped.
"""

from pathlib import Path
import argparse
import importlib.util
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "bench"
spec = importlib.util.spec_from_file_location("dev", ROOT / "tools/dev.py")
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)

# name -> the input: large enough that start-up does not matter.
BENCHMARKS = {
    "nbody": "5000000",
    "mandelbrot": "2000",
    "fib": "38",
    "tak": "18",
    "collatz": "3000000",
}


def mlton():
    local = ROOT / ".toolchain/mlton/usr/bin/mlton"
    return str(local) if local.is_file() else shutil.which("mlton")


def check(result, what):
    if result.returncode != 0:
        raise RuntimeError(f"{what} failed:\n{result.stdout}\n{result.stderr}")


def build_ours(name, work):
    src = work / "ours"
    src.mkdir()
    for f in [*(BENCH / "lib").glob("*.idr"), BENCH / name / "Main.idr"]:
        shutil.copy(f, src)
    check(dev.compile_io(src / "Main.idr", "prog"), "this compiler")
    return [src / "build/exec/prog"]


def build_chez(name, work):
    src = work / "chez"
    src.mkdir()
    for f in [*(BENCH / "lib").glob("*.idr"), BENCH / name / "Main.idr"]:
        shutil.copy(f, src)
    check(subprocess.run([dev.IDRIS_PREFIX / "bin/idris2", "--no-banner", "--no-color", "--no-prelude",
                          "-p", "idris-mlir-io", "--cg", "chez", "-o", "prog", "Main.idr"],
                         cwd=src, env=dev.idris_env(), capture_output=True, text=True), "Chez")
    return [src / "build/exec/prog"]


def build_mlton(name, work):
    compiler = mlton()
    if compiler is None:
        return None
    src = work / f"{name}.sml"
    src.write_text((BENCH / "sml/common.sml").read_text() + (BENCH / f"sml/{name}.sml").read_text())
    exe = work / f"{name}-mlton"
    # Idris's Int is 64 bits; MLton's default int is 32.
    check(subprocess.run([compiler, "-default-type", "int64", "-output", exe, src],
                         capture_output=True, text=True), "MLton")
    return [exe]


def build_c(name, work):
    exe = work / f"{name}-c"
    check(subprocess.run([dev.pinned_cc(), "-O2", BENCH / f"c/{name}.c", "-o", exe, "-lm"],
                         capture_output=True, text=True), "gcc")
    return [exe]


BUILDERS = [("this compiler", build_ours), ("Idris Chez", build_chez),
            ("MLton", build_mlton), ("gcc -O2", build_c)]


def timed(cmd, stdin, runs):
    best, out = None, None
    for _ in range(runs):
        start = time.perf_counter()
        result = subprocess.run(cmd, input=stdin.encode(), capture_output=True)
        elapsed = time.perf_counter() - start
        if result.returncode != 0:
            raise RuntimeError(f"{cmd[0]} exited {result.returncode}: {result.stderr.decode()}")
        best = elapsed if best is None else min(best, elapsed)
        out = result.stdout.decode()
    return best, out


def numbers(text):
    # SML writes a minus sign as `~`.
    return [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?(?:[eE]-?\d+)?", text.replace("~", "-"))]


def agree(a, b):
    xs, ys = numbers(a), numbers(b)
    return len(xs) == len(ys) and all(abs(x - y) <= 1e-9 * max(1.0, abs(x)) for x, y in zip(xs, ys))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("names", nargs="*")
    args = parser.parse_args()
    names = args.names or list(BENCHMARKS)
    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for name in names:
            work = Path(tmp) / name
            work.mkdir()
            times, outputs = {}, {}
            for label, build in BUILDERS:
                try:
                    cmd = build(name, work)
                except RuntimeError as err:
                    print(f"{name}: {label} failed to build: {err}", file=sys.stderr)
                    cmd = None
                if cmd is None:
                    continue
                times[label], outputs[label] = timed(cmd, BENCHMARKS[name], args.runs)
            reference = outputs.get("this compiler")
            for label, out in outputs.items():
                if label == "Idris Chez" and out != reference:
                    raise RuntimeError(f"{name}: Chez printed {out!r}, this compiler {reference!r}")
                if not agree(out, reference):
                    raise RuntimeError(f"{name}: {label} printed {out!r}, this compiler {reference!r}")
            rows.append((name, BENCHMARKS[name], times))
    labels = [label for label, _ in BUILDERS]
    print(f"Best of {args.runs} runs, wall-clock seconds; {platform.machine()}, "
          f"{os.cpu_count()} CPUs. Outputs agree.\n")
    print("| benchmark | input | " + " | ".join(labels) + " | vs MLton |")
    print("| --- | --- | " + " | ".join("---:" for _ in labels) + " | ---: |")
    for name, stdin, times in rows:
        cells = [f"{times[l]:.3f}" if l in times else "n/a" for l in labels]
        ratio = (f"{times['MLton'] / times['this compiler']:.2f}x"
                 if "MLton" in times and "this compiler" in times else "n/a")
        print(f"| {name} | {stdin} | " + " | ".join(cells) + f" | {ratio} |")


if __name__ == "__main__":
    main()
