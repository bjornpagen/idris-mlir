# lit configuration for the idr dialect tests. rule: TEST-IDR-1 Run through
# `tools/dev.py test-idr`, which puts idris-mlir-opt, idris-mlir-cc and the
# pinned FileCheck, not and count on PATH, and names the pinned C compiler.
import os
import sys

import lit.formats

config.name = "idr"
config.test_format = lit.formats.ShTest(execute_external=False)
config.suffixes = [".mlir"]
config.excludes = ["status.py", "lit.cfg.py"]
config.test_source_root = os.path.dirname(__file__)
config.test_exec_root = os.path.join(config.test_source_root, "..", "..", "build", "dev", "tests-idr")
config.environment["PATH"] = os.environ["PATH"]
config.substitutions.append(("%cc", os.environ["IDRIS_MLIR_PINNED_CC"]))
config.substitutions.append(("%status", f'"{sys.executable}" "{os.path.join(config.test_source_root, "status.py")}"'))
