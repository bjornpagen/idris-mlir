# Snapshot: type-nat-solver (Diatchki's SMT type-checker plugin for GHC)

- **Upstream:** `yav/type-nat-solver` on GitHub (https://github.com/yav/type-nat-solver).
- **Revision:** default branch at `4218b52e1f70df152daa7fc62f7f1c2ef67b60a1` (last commit
  2017-11-30).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/yav/type-nat-solver/4218b52e1f70df152daa7fc62f7f1c2ef67b60a1/<path>`.
- **Paths:** relative to the repository root.
- **Files:** 4.
- **Licence:** BSD-3-Clause, © 2014 Iavor S. Diatchki (`LICENSE`).
- **Threads:** typed-rank (Array languages and typed array programming); E.

**What is here and why.** The implementation of `diatchki-2015-smt` (whose LaTeX source,
from this repository's `docs/`, is stored in that paper folder):
`src/TypeNatSolver.hs` (the plugin: import of `Nat`/`Bool` constraints with foreign terms
named away, consistency check, improvement to constants, variables and linear relations,
solving by validity, talking SMT-LIB to an external solver); `docs/Examples.hs` (the paper's
examples); `README.mkd`; `LICENSE`.

**Not taken:** `examples/`, `tests/`, the cabal file, CI config, the rest of `docs/`. Nothing
was built or run (it targets GHC 7.10/8.0-era plugin APIs).

## File manifest

Every stored file except this one: 4 files, 34,073 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
d6a7c1e7c707a8af6e9743dccafc9f65b6fea028a663f9523c3d16e67119f095       1532  LICENSE
32014b8e6b2770117fe85262aa07b2e393be7876ac3b2972c99beb80b1432cc0        275  README.mkd
dbc39c96d53ae2b174f93df000f7821a637d15c66a297bb911c3155a811f2460        950  docs/Examples.hs
211a22a60357d082497a77b912468a18f92933a083d21c88154532b77ec236da      31316  src/TypeNatSolver.hs
```
