"""Toolchain, C++ structure and command rules (TC-*, TEST-CMD-1)."""

import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("dev", ROOT / "tools/dev.py")
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class Lock(unittest.TestCase):
    # rule: TC-PIN-1, TC-DEV-2
    def test_every_tool_is_pinned_in_the_lock(self):
        data = json.loads((ROOT / "toolchain.lock.json").read_text())
        self.assertEqual(data["schema_version"], 3)
        for tool in ("gcc", "cmake", "ninja", "llvm"):
            entry = data[tool]
            self.assertRegex(entry["revision"], r"^[0-9a-f]{40}$", tool)
            for key in ("repository", "tag", "version"):
                self.assertTrue(entry[key], f"{tool}.{key}")
        for tool in ("gcc", "cmake", "ninja"):
            self.assertTrue(data[tool]["version"].startswith(data[tool]["accept"]), tool)

    # rule: TC-DEV-2
    def test_the_configure_gate_reads_the_lock(self):
        cmake = (ROOT / "CMakeLists.txt").read_text()
        for tool in ("ninja", "cmake", "gcc"):
            self.assertIn(f'string(JSON IDRIS_MLIR_{tool.upper()}_SERIES GET "${{IDRIS_MLIR_LOCK}}" {tool} accept)', cmake)

    # rule: TC-PIN-2
    def test_stale_stamps_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory)
            with self.assertRaisesRegex(ValueError, "bootstrap-gcc"):
                dev.stamped(prefix, "gcc")
            (prefix / "provenance.json").write_text(json.dumps({"revision": "0" * 40}))
            with self.assertRaisesRegex(ValueError, "stale"):
                dev.stamped(prefix, "gcc")
            dev.write_stamp(prefix, "gcc")
            self.assertEqual(dev.stamped(prefix, "gcc"), prefix)


class Bootstrap(unittest.TestCase):
    # rule: TC-BOOT-1, TEST-CMD-1
    def test_commands_exist(self):
        source = (ROOT / "tools/dev.py").read_text()
        for command in ("bootstrap-gcc", "bootstrap-cmake", "bootstrap-ninja", "bootstrap-llvm",
                        "bootstrap-idris", "check", "build", "test", "test-idr",
                        "test-mlir-tools", "compile"):
            self.assertIn(f'"{command}"', source)

    # rule: TC-BOOT-2
    def test_llvm_is_built_with_the_pinned_tools(self):
        calls = []
        pinned = {"pinned_cc": Path("/p/gcc"), "pinned_cxx": Path("/p/g++"),
                  "pinned_cmake": Path("/p/cmake"), "pinned_ninja": Path("/p/ninja")}
        with tempfile.TemporaryDirectory() as directory, \
                patch.multiple(dev, **{k: (lambda v=v: v) for k, v in pinned.items()}), \
                patch.object(dev, "LLVM_PREFIX", Path(directory) / "llvm"), \
                patch.object(dev, "clone_pinned", lambda *a: None), \
                patch.object(dev, "require", lambda *a: None), \
                patch.object(dev, "run", lambda args, **kw: calls.append([str(a) for a in args])), \
                patch.object(dev.shutil, "copy2", lambda *a: None):
            dev.bootstrap_llvm()
        configure = calls[0]
        self.assertEqual(configure[0], "/p/cmake")
        for flag in ("-DCMAKE_C_COMPILER=/p/gcc", "-DCMAKE_CXX_COMPILER=/p/g++",
                     "-DCMAKE_MAKE_PROGRAM=/p/ninja", "-DLLVM_ENABLE_PROJECTS=mlir"):
            self.assertIn(flag, configure)
        self.assertTrue(all(call[0] == "/p/cmake" for call in calls))

    # rule: TC-BOOT-3
    def test_lit_comes_from_the_pinned_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            lit = Path(directory) / "llvm/utils/lit/lit.py"
            lit.parent.mkdir(parents=True)
            lit.touch()
            with patch.object(dev, "LLVM_SOURCE", Path(directory)):
                self.assertEqual(dev.lit_command()[1], lit)

    # rule: TC-CPP-2, TC-LIB-1
    def test_build_uses_the_preset_and_installs_the_io_package(self):
        calls = []
        with patch.object(dev, "pinned_cmake", lambda: Path("/p/cmake")), \
                patch.object(dev, "pinned_cc", lambda: Path("/p/gcc")), \
                patch.object(dev, "llvm_bin", lambda: Path("/p/llvm/bin")), \
                patch.object(dev, "idris_env", lambda: {}), \
                patch.object(dev, "write_paths", lambda: None), \
                patch.object(dev, "run", lambda args, **kw: calls.append([str(a) for a in args])):
            dev.build()
        self.assertEqual(calls[0], ["/p/cmake", "--preset", "dev"])
        self.assertEqual(calls[1], ["/p/cmake", "--build", "--preset", "dev"])
        self.assertIn(["idris2", "--install", "idris-mlir-io.ipkg"], calls)


class Structure(unittest.TestCase):
    # rule: TC-LAYOUT-1
    def test_layout(self):
        for path in ("CMakeLists.txt", "CMakePresets.json", "PINS.md", "toolchain.lock.json",
                     "compiler/idris-mlir.ipkg", "lib/idris-mlir-io/idris-mlir-io.ipkg",
                     "foreign/idr/CMakeLists.txt", "src/CMakeLists.txt", "unsafe/CMakeLists.txt",
                     "tests/tooling", "tests/compiler", "tests/profile/v0", "tests/profile/v1",
                     "tests/idr", "tests/e2e/v0", "tests/e2e/v1", "docs/cpp-profile.md"):
            self.assertTrue((ROOT / path).exists(), path)

    # rule: TC-CPP-1
    def test_cpp_starter_adoption(self):
        profile = (ROOT / "docs/cpp-profile.md").read_text()
        self.assertIn("bdb6838", profile)
        presets = json.loads((ROOT / "CMakePresets.json").read_text())
        names = {p["name"] for p in presets["configurePresets"]}
        self.assertTrue({"dev", "release", "asan-ubsan", "lint"} <= names)
        cmake = (ROOT / "CMakeLists.txt").read_text()
        for flag in ("set(CMAKE_CXX_STANDARD 26)", "-fno-exceptions -fno-rtti", "-freflection",
                     "-Werror", "idris_mlir_language_profile"):
            self.assertIn(flag, cmake)

    # rule: TC-ZONE-1, TC-ZONE-2
    def test_zones(self):
        cpp = [p for p in ROOT.rglob("*") if p.suffix in {".cpp", ".h", ".hpp", ".cc", ".td", ".inc"}
               and not any(part in {"third_party", ".toolchain", "build", ".git", "docs"}
                           for part in p.relative_to(ROOT).parts)]
        self.assertTrue(cpp)
        for path in cpp:
            self.assertEqual(path.relative_to(ROOT).parts[:2], ("foreign", "idr"), path)
        for zone in ("src", "unsafe"):
            self.assertEqual(sorted(p.name for p in (ROOT / zone).iterdir()), ["CMakeLists.txt"])

    # rule: TC-DEV-1, TC-DEV-3, TC-DEV-4, TC-DEV-5
    def test_deviations_are_pinned(self):
        cmake = (ROOT / "CMakeLists.txt").read_text()
        self.assertIn("x86_64", cmake)
        self.assertIn("PIN(lint-graph-unbuilt)", cmake)
        self.assertNotIn("stdexec", cmake.replace("no-stdexec", ""))
        pins = (ROOT / "PINS.md").read_text()
        for name in ("platform-gate-x86_64", "lint-graph-unbuilt", "no-stdexec", "llvm-cxx17-headers"):
            self.assertIn(f"## {name}", pins)

    def test_every_pin_site_has_an_entry_and_back(self):
        pins = (ROOT / "PINS.md").read_text()
        entries = set(re.findall(r"^## (\S+)$", pins, re.M))
        sites = set()
        for path in ROOT.rglob("*"):
            if path.is_file() and path.suffix != ".md" and \
                    not any(part in {"third_party", ".toolchain", "build", ".git", "docs"}
                            for part in path.relative_to(ROOT).parts):
                try:
                    sites |= set(re.findall(r"PIN\(([\w-]+)\)", path.read_text()))
                except (UnicodeDecodeError, OSError):
                    pass
        self.assertTrue(sites <= entries, sites - entries)


if __name__ == "__main__":
    unittest.main()
