"""Test dependency rejection and isolation from unrelated compiler installs."""

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("dev", ROOT / "tools/dev.py")
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class DependencyTests(unittest.TestCase):
    def test_actual_submodule_matches_lock(self):
        dev.verify_pins()

    def test_revision_drift_is_rejected(self):
        data = dev.lock()
        data["idris2"]["revision"] = "0" * 40
        with patch.object(dev, "lock", return_value=data):
            with self.assertRaisesRegex(ValueError, "lock requires"):
                dev.verify_pins()

    def test_local_build_environment_does_not_inherit_package_paths(self):
        with patch.dict(os.environ, {"IDRIS2_PATH": "/unrelated", "IDRIS2_PACKAGE_PATH": "/unrelated",
                                    "IDRIS2_INC_CGS": "other", "IDRIS2_PREFIX": "/unrelated"}):
            env = dev.local_env()
        self.assertNotIn("IDRIS2_PATH", env)
        self.assertNotIn("IDRIS2_PACKAGE_PATH", env)
        self.assertNotIn("IDRIS2_INC_CGS", env)
        self.assertEqual(env["IDRIS2_PREFIX"], str(dev.PREFIX))

    def test_missing_mlir_configuration_fails_with_actionable_error(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [sys.executable, ROOT / "tools/dev.py", "configure-mlir", "--mlir-dir", directory],
                capture_output=True, text=True,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MLIRConfig.cmake not found", result.stderr)

    def test_failed_bootstrap_cannot_look_like_an_installed_toolchain(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory)
            (prefix / "bin").mkdir()
            (prefix / "bin/idris2").touch()
            with patch.object(dev, "PREFIX", prefix):
                with self.assertRaisesRegex(ValueError, "bootstrap-idris"):
                    dev.installed_env(dev.lock())


if __name__ == "__main__":
    unittest.main()
