"""Integration tests using the real frontend; no stdout-only success checks."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def invoke(frontend, cwd, source, success=True):
    result = subprocess.run(
        [frontend, "--no-banner", "--no-color", "--no-prelude",
         "--cg", "core-inspect", "--inc", "core-inspect", "--check", source],
        cwd=cwd, capture_output=True, text=True,
    )
    if (result.returncode == 0) != success:
        raise AssertionError(f"Unexpected status {result.returncode}:\n{result.stdout}\n{result.stderr}")
    return result


def main():
    frontend = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix="idris-mlir-test-") as directory:
        work = Path(directory)
        for fixture in FIXTURES.glob("*.idr"):
            shutil.copy2(fixture, work / fixture.name)
        invoke(frontend, work, "Vectors.idr")
        summaries = list(work.glob("build/ttc/**/Vectors.ttsummary"))
        if len(summaries) != 1:
            raise AssertionError(f"Expected one summary, found {summaries}")
        summary = summaries[0]
        text = summary.read_text()
        lines = text.splitlines()
        assert lines[0] == "idris-mlir-tt-summary\t1", text
        rows = {}
        for line in lines[1:]:
            fields = line.split("\t")
            assert fields[0] == "definition", line
            rows[fields[1]] = dict(field.split("=", 1) for field in fields[2:])
        assert rows["Vectors.keep"]["quantities"] == "Rig0,RigW", text
        assert rows["Vectors.append"]["clauses"] == "2", text
        assert rows["Vectors.append"]["type"] == "present", text
        assert rows["Vectors.runtimeLength"]["quantities"].split(",").count("RigW") >= 2, text
        before = (summary.read_bytes(), summary.stat().st_mtime_ns)
        invoke(frontend, work, "Vectors.idr")
        assert (summary.read_bytes(), summary.stat().st_mtime_ns) == before, "Warm cache rewrote the summary"
        invoke(frontend, work, "BadErase.idr", success=False)
        assert not list(work.glob("build/ttc/**/BadErase.ttsummary")), "Failed module produced a summary"
    print("Frontend quantities, checked clauses, warm cache, and erasure rejection passed")


if __name__ == "__main__":
    main()
