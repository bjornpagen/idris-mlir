# Snapshot: Rocq reference manual, rewriting, generalisation and arithmetic solvers

- **Upstream:** `rocq-prover/rocq` on GitHub (https://github.com/rocq-prover/rocq), the Sphinx
  sources of the reference manual (rendered at https://rocq-prover.org/doc/).
- **Revision:** default branch at `29f5238ebcc99136c8e695babcb658ade8d96fa4`, the HEAD resolved
  with `git ls-remote` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/rocq-prover/rocq/29f5238ebcc99136c8e695babcb658ade8d96fa4/<path>`.
- **Paths:** relative to the repository root (so `doc/sphinx/...`).
- **Files:** 6.
- **Licence:** Open Publication License v1.0 or later, options A and B not elected
  (`doc/LICENSE`); the repository's own `LICENSE` (LGPL-2.1) covers the code, not the manual.
- **Threads:** dependent-equality (Array languages and typed array programming).

**What is here and why.**
- `doc/sphinx/proofs/writing-proofs/equality.rst`: `rewrite` (lines 108–230: the first matched
  instance fixes the pattern, occurrences, `setoid_rewrite` for occurrences under binders).
- `doc/sphinx/proof-engine/tactics.rst`: `generalize` (from line 1636), `generalize dependent`
  (1666–1669); `apply`'s second-order case, which abstracts `t1 … tn` from the target to
  instantiate a motive `P`, and `pattern` to do it by hand (722–731).
- `doc/sphinx/proofs/writing-proofs/reasoning-inductives.rst`: `dependent rewrite` on equalities
  of dependent pairs (1181–1194); `dependent destruction`/`dependent induction` and
  `generalize_eqs`, stated as McBride's BasicElim (1698–1800).
- `doc/sphinx/addendum/ring.rst`: `ring`, normalisation of (semi)ring polynomials to a canonical
  sum by reflection (lines 13–150).
- `doc/sphinx/addendum/micromega.rst`: `lia` (linear integer arithmetic by Positivstellensatz
  refutations and cutting planes, lines 184–231), `nia`.
- `doc/LICENSE`.

**Not taken:** the plugin sources (`plugins/ring`, `plugins/micromega`), `Program.Equality`.
To fetch more, use the raw URL pattern above at this revision. Nothing was built or run.

## File manifest

Every stored file except this one: 6 files, 277,141 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
11663c87ea837ffc7fa1c22f5c36f8f6e6b60743f8e57e99acd59ba98a2ddd9d      31318  doc/LICENSE
7a91f0ca4ee24fdb406be9ac4d0a19e4dc62994d5613dc246a7b81794d14aa2a      20702  doc/sphinx/addendum/micromega.rst
64c8b6f1d84e60946e25392eb0676e57bb8a34585cd9f50ded98e92110c53d56      31253  doc/sphinx/addendum/ring.rst
6fb01bfb4ee1d51e91ed7ad75bc76ff9050672437c43eddc1377f03ced351095      69026  doc/sphinx/proof-engine/tactics.rst
6bf5843545727ad94ce267d2ab3d7d6d726307b5b0700b0277c4e90809233947      51654  doc/sphinx/proofs/writing-proofs/equality.rst
4cb5d760cb4b3e3e5411a42eba27ee9ca4ccb10dcfbc91ccc95f92ee2bee1098      73188  doc/sphinx/proofs/writing-proofs/reasoning-inductives.rst
```
