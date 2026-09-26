"""The test harness shared by `dev.py test` suites (TEST-CMD-1).

Tests check exit status and produced artifacts, never just stdout. A test
that cannot run is skipped with its reason and never counted as passed.
"""

from concurrent.futures import ThreadPoolExecutor
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
import traceback

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("dev", ROOT / "tools/dev.py")
dev = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dev)


class Skip(Exception):
    """A test that cannot run here, with the reason."""


class Results:
    def __init__(self):
        self.passed, self.failed, self.skipped = [], [], []
        self.lock = threading.Lock()

    def record(self, name, outcome, detail=""):
        with self.lock:
            {"pass": self.passed, "fail": self.failed, "skip": self.skipped}[outcome].append((name, detail))
            mark = {"pass": "PASS", "fail": "FAIL", "skip": "SKIP"}[outcome]
            print(f"{mark} {name}" + (f": {detail.splitlines()[0]}" if detail and outcome == "skip" else ""),
                  flush=True)
            if outcome == "fail":
                print("  " + detail.replace("\n", "\n  "), flush=True)

    def summary(self):
        return f"{len(self.passed)} passed, {len(self.failed)} failed, {len(self.skipped)} skipped"


def run_cases(results, cases, jobs=None):
    """Runs (name, function) pairs, in parallel; each function raises
    AssertionError to fail and Skip to skip."""
    def one(case):
        name, fn = case
        try:
            fn()
        except Skip as skip:
            results.record(name, "skip", str(skip))
        except AssertionError as error:
            results.record(name, "fail", str(error))
        except Exception:  # noqa: BLE001 - an unexpected error is a failure
            results.record(name, "fail", traceback.format_exc())
        else:
            results.record(name, "pass")
    with ThreadPoolExecutor(max_workers=jobs or os.cpu_count() or 1) as pool:
        list(pool.map(one, cases))


def workdir(prefix):
    return Path(tempfile.mkdtemp(prefix=f"idris-mlir-{prefix}-"))


def copy_fixture(source, dest):
    """Copies a fixture file or directory into `dest`."""
    source = Path(source)
    if source.is_dir():
        for path in source.iterdir():
            if path.is_file():
                shutil.copy2(path, dest / path.name)
    else:
        shutil.copy2(source, dest / source.name)


def llvm_tool(name):
    tool = dev.llvm_bin() / name
    if not tool.is_file():
        raise Skip(f"{name} is not built; run tools/dev.py bootstrap-llvm")
    return tool


def stock_idris():
    """The pinned stock Idris 2 (the reference implementation, SEM-REF-1)."""
    return dev.IDRIS_PREFIX / "bin/idris2"


def limit_stack():
    """Programs under test run on a 1 MiB stack (SEM-RES-2)."""
    import resource
    resource.setrlimit(resource.RLIMIT_STACK, (2 ** 20, 2 ** 20))


def run(args, cwd, stdin=None, env=None, timeout=600, small_stack=False):
    return subprocess.run([str(a) for a in args], cwd=cwd, input=stdin, env=env,
                          capture_output=True, timeout=timeout,
                          preexec_fn=limit_stack if small_stack else None)


def text(process):
    out = process.stdout if isinstance(process.stdout, str) else process.stdout.decode(errors="replace")
    err = process.stderr if isinstance(process.stderr, str) else process.stderr.decode(errors="replace")
    return out + err


# rule: TEST-HEAP-1, LOW-EXT-1
def assert_heap_free(obj, allowed):
    """The object file's undefined symbols are a subset of `allowed`."""
    nm = run([llvm_tool("llvm-nm"), "--undefined-only", "--format=just-symbols", obj], obj.parent)
    assert nm.returncode == 0, text(nm)
    symbols = set(nm.stdout.decode().split())
    extra = symbols - set(allowed)
    assert not extra, f"{obj.name} needs {sorted(extra)}; only {sorted(allowed)} are allowed"


def artifacts(work, pattern):
    return sorted(p for p in Path(work).glob(f"build/**/{pattern}") if p.is_file())


LOCATION = re.compile(r"(?:^|\s)[\w/.-]+:(\d+):(\d+)--(\d+):(\d+)\b")


def reported_line(output):
    """The first line number of the first Idris location in the output."""
    match = LOCATION.search(output)
    return int(match.group(1)) if match else None
