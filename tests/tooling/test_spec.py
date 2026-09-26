"""TEST-SPEC-1: rule identifiers in docs/architecture/ against the tests."""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "docs/architecture"
TESTS = ROOT / "tests"
ORDER = ["p0", "v0", "v1", "v2", "v3"]

# A rule starts with a bold identifier, an optional version, then a period.
RULE = re.compile(r"^\s*(?:[-*]\s+)?\*\*([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-[0-9]+)(?: \(([^)]*)\))?\.")
REFERENCE = re.compile(r"\b([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-[0-9]+)\b")


def rules():
    """Every rule: identifier -> (version or None, text of the rule)."""
    found = {}
    duplicates = []
    for path in sorted(SPEC.glob("*.md")):
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            match = RULE.match(line)
            if not match:
                continue
            ident, version = match.group(1), match.group(2)
            body = [line]
            for rest in lines[i + 1:]:
                if RULE.match(rest) or rest.startswith("#"):
                    break
                body.append(rest)
            if ident in found:
                duplicates.append(ident)
            found[ident] = (version, "\n".join(body))
    return found, duplicates


def implemented():
    version = (SPEC / "VERSION").read_text().strip()
    return ORDER[:ORDER.index(version) + 1]


def exempt(version, body):
    """Planned, checked by review, or without a version (principles, reserved)."""
    if version is None or version == "reserved":
        return True
    if "*planned*" in body:
        return True
    return re.search(r"(Check|Test): [^\n]*\breview\b", body) is not None


def in_versions(version, versions):
    base = version.split()[0].rstrip("+,")
    if "only" in version and versions[-1] != base:
        return False   # superseded by a rule of a later version
    return base in versions


def references():
    """Identifiers referenced by test files: in a file or directory name, or
    in a `rule: <ID>` comment."""
    refs = {}
    for path in TESTS.rglob("*"):
        if "__pycache__" in path.parts or "build" in path.parts:
            continue
        for part in path.relative_to(TESTS).parts:
            for ident in REFERENCE.findall(part):
                refs.setdefault(ident, set()).add(path)
        if path.is_file() and path.suffix in {".py", ".idr", ".mlir", ".check", ".cfg", ""}:
            try:
                text = path.read_text()
            except UnicodeDecodeError:
                continue
            for line in text.splitlines():
                for match in re.finditer(r"rule: ([A-Z0-9-]+(?:,\s*[A-Z0-9-]+)*)", line):
                    for ident in re.split(r",\s*", match.group(1)):
                        refs.setdefault(ident, set()).add(path)
    return refs


class SpecConformance(unittest.TestCase):
    def test_version_file(self):
        self.assertIn((SPEC / "VERSION").read_text().strip(), ORDER)

    def test_no_rule_is_defined_twice(self):
        _, duplicates = rules()
        self.assertEqual(duplicates, [])

    def test_every_referenced_rule_exists(self):
        found, _ = rules()
        # Identifier-shaped words that are not rules (names, not references).
        unknown = {ident: sorted(str(p.relative_to(ROOT)) for p in paths)
                   for ident, paths in references().items() if ident not in found}
        self.assertEqual(unknown, {})

    def test_every_implemented_rule_is_tested(self):
        found, _ = rules()
        versions = implemented()
        refs = references()
        missing = sorted(ident for ident, (version, body) in found.items()
                         if not exempt(version, body) and in_versions(version, versions)
                         and ident not in refs)
        self.assertEqual(missing, [], f"{len(missing)} implemented rules have no test")


if __name__ == "__main__":
    unittest.main()
