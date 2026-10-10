# Snapshot: Lean reference manual, release notes on parallel elaboration

- **Upstream:** `leanprover/reference-manual` on GitHub
  (https://github.com/leanprover/reference-manual); rendered at
  https://lean-lang.org/doc/reference/latest/releases/.
- **Revision:** default branch at `349244b4dd2f284728c1dacb621cc74a32f9929b`, the HEAD resolved
  with `git ls-remote` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/leanprover/reference-manual/349244b4dd2f284728c1dacb621cc74a32f9929b/<path>`.
  All 49 release-note files were fetched to find the parallelism entries; five are kept.
- **Paths:** relative to the repository root.
- **Licence:** Apache-2.0 (`LICENSE`, byte-identical to the Lean 4 `LICENSE`).
- **Threads:** elaborators (Fast dependent type checking and elaboration).

**What is here and why.**
- `Manual/Releases/v4_8_0.lean`: snapshot trees (#3014), the foundation for incrementality
  and parallelism (line 183).
- `Manual/Releases/v4_17_0.lean`: kernel checking in parallel to elaboration (#6368, lines
  33–34) and the API for parallel environment changes (#6691, line 441).
- `Manual/Releases/v4_18_0.lean`: "Parallelizing Elaboration": code generation in parallel
  (#6770), lazy helper declarations across threads (#7076) (lines 417–431).
- `Manual/Releases/v4_19_0.lean`: parallel elaboration of theorem bodies (#7084, lines 50–53
  and 390–408); well-founded definitions made opaque because kernel reduction of them "tends
  to be prohibitively slow" (#5182).
- `Manual/Releases/v4_23_0.lean`: `Lean.realizeValue`, parallelism-aware caching of `MetaM`
  computations (#9798, line 697).
- `LICENSE`.

**Measurements:** none of these entries reports a speedup figure.

**Not taken:** the other 44 release-note files and the manual itself. Nothing was built or
run.

## File manifest

Every stored file except this one: 6 files, 304,839 bytes in all.

```
SHA-256                                                               bytes  path
8b28515ffffc5c0fe2807d8ae3735b00b324d9b7ce807dd63ff6ac8922fbce7e       9160  LICENSE
17bfc5ede3fbfa1d3e94f42547edbaa36986835e92af8c86046e944deeaa1e1d      55420  Manual/Releases/v4_17_0.lean
e99ae6c2fadcb0f6b5b1b53d85ac59b93a2925f1f55e8eb75056f0195d05b70c      59530  Manual/Releases/v4_18_0.lean
f4f32c031d603ab8ad4368301c283a2803c22c889b035cf08e63e2a4ed56aa28      69669  Manual/Releases/v4_19_0.lean
be9748eb7c4f09b534dc9ad07bede289d3f591da8165353e6b0b2fc0133ee983      69921  Manual/Releases/v4_23_0.lean
a1e323534832522f92e495aabc7cdfb2938cadd05a01141bbf37f59da0cfd503      41139  Manual/Releases/v4_8_0.lean
```
