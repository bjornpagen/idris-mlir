"""Profile fixtures (TEST-REJ-1, TEST-ACC-1, TEST-VER-1).

A fixture is `tests/profile/vN/{accept,reject}/<RULE-ID>-<desc>.idr`, or a
directory of that name holding `Main.idr` and its other user modules. Its
first line states the expectation:

    -- expect: <RULE-ID> line <n>      (reject)
    -- message: <text>                 (reject, optional: in the message)
    -- exit: <status>                  (accept, optional: also run it)
    -- stdout: <text with \\n escapes>  (accept, optional)

A single-file fixture is compiled as `Main.idr`. A program whose `main` has
type `IO` goes through DRV-FLOW-2, any other through DRV-FLOW-1.
"""

from pathlib import Path
import re

from harness import (artifacts, dev, reported_line, run, text, workdir)

HERE = Path(__file__).resolve().parent
HEADER = re.compile(r"^--\s*(expect|message|exit|stdout):\s*(.*)$")


def header(source):
    fields = {}
    for line in source.read_text().splitlines():
        match = HEADER.match(line)
        if not match:
            break
        fields[match.group(1)] = match.group(2)
    return fields


def prepare(fixture):
    work = workdir("profile")
    if fixture.is_dir():
        for path in fixture.iterdir():
            (work / path.name).write_bytes(path.read_bytes())
    else:
        (work / "Main.idr").write_bytes(fixture.read_bytes())
    return work, work / "Main.idr"


def compile_fixture(work, main):
    """Returns (succeeded, output, executable or None)."""
    if dev.is_io_program(main):
        result = dev.compile_io(main, "Main")
        exe = work / "build/exec/Main"
        return result.returncode == 0, text(result), exe, result.returncode
    steps = dev.compile_int(main, work / "build/exec/Main")
    last = steps[-1]
    ok = len(steps) == 3 and last.returncode == 0
    return ok, "".join(text(s) for s in steps), work / "build/exec/Main", steps[0].returncode


# rule: TEST-REJ-1, FE-ART-1, DIAG-FMT-1, DIAG-LOC-1, DIAG-EXIT-1, DIAG-CODE-1, DIAG-ONE-1, PROF-GEN-2
def reject_case(fixture):
    def case():
        main_file = fixture / "Main.idr" if fixture.is_dir() else fixture
        fields = header(main_file)
        match = re.match(r"([A-Z0-9-]+) line (\d+)$", fields.get("expect", ""))
        assert match, f"{fixture.name}: first line must be '-- expect: <RULE-ID> line <n>'"
        rule, line = match.group(1), int(match.group(2))
        assert fixture.name.startswith(rule), f"{fixture.name} does not start with {rule}"
        work, main = prepare(fixture)
        ok, output, _, status = compile_fixture(work, main)
        assert not ok and status == 1, f"expected exit status 1, got {status}:\n{output}"
        assert f"unsupported ({rule})" in output, f"expected unsupported ({rule}):\n{output}"
        assert output.count("unsupported (") == 1, f"expected exactly one error:\n{output}"
        assert reported_line(output) == line, f"expected line {line}, got {reported_line(output)}:\n{output}"
        if "message" in fields:
            assert fields["message"] in output, f"expected {fields['message']!r} in:\n{output}"
        left = artifacts(work, "*.core") + artifacts(work, "*.mlir") + artifacts(work, "*.o")
        assert not left, f"artifacts left after a rejection: {left}"
    return case


# rule: TEST-ACC-1, TEST-VER-1, PROF-GEN-4
def accept_case(fixture):
    def case():
        main_file = fixture / "Main.idr" if fixture.is_dir() else fixture
        fields = header(main_file)
        work, main = prepare(fixture)
        ok, output, exe, status = compile_fixture(work, main)
        assert ok, f"compilation failed ({status}):\n{output}"
        for pattern in ("Main.core", "Main.mlir", "Main.o"):
            found = artifacts(work, pattern)
            assert found and all(p.stat().st_size > 0 for p in found), f"missing {pattern}"
        assert exe.is_file(), "missing executable"
        if "exit" in fields or "stdout" in fields:
            result = run([exe], work)
            if "exit" in fields:
                assert result.returncode == int(fields["exit"]), \
                    f"exit {result.returncode}, expected {fields['exit']}"
            expected = fields.get("stdout", "").encode().decode("unicode_escape").encode("latin-1")
            assert result.stdout == expected.decode("utf-8").encode(), \
                f"stdout {result.stdout!r}, expected {expected!r}"
            assert result.stderr == b"", f"stderr: {result.stderr!r}"
    return case


def cases(filter_text=""):
    found = []
    for version in sorted(HERE.glob("v*")):
        for kind, make in (("reject", reject_case), ("accept", accept_case)):
            for fixture in sorted((version / kind).glob("*")):
                if fixture.suffix != ".idr" and not fixture.is_dir():
                    continue
                name = f"profile/{version.name}/{kind}/{fixture.stem}"
                if filter_text in name:
                    found.append((name, make(fixture)))
    return found

