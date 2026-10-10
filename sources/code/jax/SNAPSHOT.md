# Snapshot: JAX symbolic shapes (shape polymorphism) implementation

- **Upstream:** `jax-ml/jax` on GitHub.
- **Revision:** `main` at `40a35abdd67b2298decb7d14e89adf4d120f1902` (the revision of
  `docs/jax/`).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/jax-ml/jax/40a35abdd67b2298decb7d14e89adf4d120f1902/<path>`
  (HTTP 200 each).
- **Paths:** relative to the repository root (so `jax/_src/export/shape_poly.py`).
- **Files:** 2.
- **Licence:** Apache-2.0 (each file carries the Apache-2.0 header).
- **Threads:** G (topic: Array languages and typed array programming / shapes).

**What is here and why.**

- `jax/_src/export/shape_poly.py` — symbolic dimension expressions: `_DimFactor` (a
  variable, or `floordiv`, `mod`, `max`, `min` of expressions), `_DimTerm` (a product of
  factors), `_DimExpr` (a sorted linear combination of terms with integer coefficients, in a
  normal form), symbolic scopes and constraints, and the solving of dimension variables
  from input shapes at call time.
- `jax/_src/export/shape_poly_decision.py` — `_DecisionByElimination`, the bounds
  procedure behind symbolic comparisons: it eliminates a term between the expression and a
  constraint `c >= 0` to derive lower and upper bounds.

Only these two files were taken: they hold the whole symbolic-dimension algebra and its
decision procedure, which is what a typed array language compares its own shape
arithmetic with. Read only; nothing was run.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `jax/_src/export/shape_poly.py` | 87,073 | `73033a7863c8451fc7882636e61f888191b5220f439306e30f82ead5de493687` |
| `jax/_src/export/shape_poly_decision.py` | 20,878 | `3e116c3ff743e64d6255c42d53e8641c8320a8670827aeef6095a821ff53325f` |

**How to fetch more.** Same base as `docs/jax/SNAPSHOT.md`. Related modules at this
revision: `jax/_src/export/_export.py` (lowering and the calling convention),
`jax/_src/interpreters/mlir.py` (lowering to StableHLO).
