"""Tests for tools/dev.py and repository-wide rules."""

import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("dev", ROOT / "tools/dev.py")
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class ToolingTests(unittest.TestCase):
    def test_idris_checkout_matches_staged_pin(self):
        dev.verify_idris_source()

    def test_idris_checkout_drift_is_rejected(self):
        real_git = dev.git

        def fake_git(*args, cwd=dev.ROOT):
            if args[:2] == ("rev-parse", "HEAD"):
                return "0" * 40
            return real_git(*args, cwd=cwd)

        with patch.object(dev, "git", fake_git):
            with self.assertRaisesRegex(ValueError, "staged pin"):
                dev.verify_idris_source()

    def test_doctor_reports_missing_idris_source_without_failing(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(dev, "IDRIS_SOURCE", Path(directory)):
                with patch("builtins.print") as output:
                    dev.doctor()
        printed = " ".join(str(arg) for call in output.call_args_list for arg in call.args)
        self.assertIn("git submodule update --init", printed)

    def test_local_build_environment_does_not_inherit_package_paths(self):
        with patch.dict(os.environ, {"IDRIS2_PATH": "/unrelated", "IDRIS2_PACKAGE_PATH": "/unrelated",
                                     "IDRIS2_INC_CGS": "other", "IDRIS2_PREFIX": "/unrelated"}):
            env = dev.local_env()
        self.assertNotIn("IDRIS2_PATH", env)
        self.assertNotIn("IDRIS2_PACKAGE_PATH", env)
        self.assertNotIn("IDRIS2_INC_CGS", env)
        self.assertEqual(env["IDRIS2_PREFIX"], str(dev.IDRIS_PREFIX))

    def test_failed_bootstrap_cannot_look_like_an_installed_toolchain(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory)
            (prefix / "bin").mkdir()
            (prefix / "bin/idris2").touch()
            with patch.object(dev, "IDRIS_PREFIX", prefix):
                with self.assertRaisesRegex(ValueError, "bootstrap-idris"):
                    dev.idris_env()
            with patch.object(dev, "LLVM_PREFIX", prefix):
                with self.assertRaisesRegex(ValueError, "bootstrap-llvm"):
                    dev.llvm_bin()

    def test_missing_mlir_tools_fail_the_smoke_test(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [sys.executable, ROOT / "tests/mlir/check_pipeline.py", directory],
                capture_output=True, text=True,
            )
        self.assertNotEqual(result.returncode, 0)

    def test_only_the_frontend_imports_the_idris_compiler(self):
        package = (dev.IDRIS_SOURCE / "idris2api.ipkg").read_text()
        modules = package.split("modules", 1)[1]
        roots = set(re.findall(r"^\s*,?\s*([A-Z][A-Za-z0-9]*)[.,\s]", modules, re.MULTILINE))
        self.assertIn("Core", roots)
        source = ROOT / "compiler/src"
        frontend = source / "IdrisMLIR/Frontend"
        for path in source.rglob("*.idr"):
            if frontend in path.parents:
                continue
            for imported in re.findall(r"^import\s+(?:public\s+)?([\w.]+)", path.read_text(), re.MULTILINE):
                self.assertNotIn(imported.split(".")[0], roots, f"{path} imports {imported}")


if __name__ == "__main__":
    unittest.main()
