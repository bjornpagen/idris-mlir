# Snapshot: tinygrad modules

- **Upstream:** `tinygrad/tinygrad` on GitHub.
- **Revision:** `master` at `b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a`.
- **Fetched:** 2026-09-26, from
  `https://raw.githubusercontent.com/tinygrad/tinygrad/b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a/<path>`.
- **Paths:** relative to the repository root (so `tinygrad/uop/ops.py`).
- **Files:** 19.
- **Licence:** MIT.
- **Threads:** A, G, H.

**What is here.** The Thread A module set:
- `tinygrad/uop/`: `__init__.py`, `ops.py`, `upat.py`, `spec.py`, `symbolic.py`,
  `render.py`, `validate.py`;
- `tinygrad/codegen/simplify.py`;
- `tinygrad/schedule/`: `prepare.py`, `rangeify.py`, `indexing.py`, `memory.py`, `multi.py`;
- `tinygrad/renderer/`: `cstyle.py`, `llvmir.py`;
- `tinygrad/engine/`: `realize.py`, `jit.py`;

plus `tinygrad/codegen/opt/search.py`, the BEAM search module, and
`tinygrad/codegen/opt/heuristic.py`. The manifest said to locate the BEAM search module at
fetch time; it was located from the pinned `tinygrad/codegen/{opt,late,decomp}` trees, not
guessed.
