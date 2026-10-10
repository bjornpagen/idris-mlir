# Snapshot addendum: MLIR SMT dialect, SMT-LIB export, Presburger library (merge into `code/mlir/SNAPSHOT.md`)

This adds 19 files to the existing `code/mlir/` snapshot; it duplicates none of its 94 and
none of the 38 the array-stack addendum (`apl` staging, `code/mlir/SNAPSHOT.addendum.md`)
adds. The library already holds `include/mlir/Dialect/Transform/SMTExtension/*` (the `.td` and
headers); this addendum adds its implementation file. Merge this section into
`code/mlir/SNAPSHOT.md` when the staged library is applied; upstream, revision, paths and
licence are unchanged. Written by the decision-procedures cluster of the 2026-10-09 pass.

- **Upstream:** `llvm/llvm-project`, the `mlir/` component.
- **Revision:** llvm main at commit `7208ba24ca2894729cd394475a00d2a7b605e642` (`mlir` subtree
  `ec52aa1c2a6f38a131b8edffc6390e1c60cbc4e0`), the repository's LLVM pin.
- **Fetched:** 2026-10-09, from the bootstrap's clone: each file taken with
  `git -C .toolchain/llvm-project cat-file blob 7208ba24…:mlir/<path>`. Nothing was downloaded.
- **Paths:** relative to `llvm-project/mlir/`.
- **Files added:** 19.
- **Licence:** Apache-2.0 WITH LLVM-exception.
- **Threads:** F, I; decision-procedures (Fast dependent type checking and elaboration).

**What was taken and why.** What MLIR at the pin offers a type checker that wants a solver:
- The `smt` dialect, whose documentation upstream generates from these files (there is no
  `docs/Dialects/SMT.md` at the pin): `include/mlir/Dialect/SMT/IR/{SMT,SMTDialect,SMTTypes,
  SMTAttributes,SMTOps,SMTBitVectorOps,SMTIntOps,SMTArrayOps}.td` (`smt.solver` as an isolated
  solver lifetime, `set_logic`, `assert`, `push`, `pop`, `reset`, `check` with sat/unknown/unsat
  regions, `declare_fun`, `apply_func`, quantifiers with patterns and weights; Bool, Int,
  bit-vector, array, function and uninterpreted-sort types).
- SMT-LIB export: `include/mlir/Target/SMTLIB/ExportSMTLIB.h` (the three emission options),
  `lib/Target/SMTLIB/ExportSMTLIB.cpp` (the emitter: it prints `(check-sat)` only for a
  `smt.check` with empty regions and no results, lines 576–590; refuses solver scopes with
  inputs or results, lines 626–628; refuses `no_pattern`, line 299, and `int2bv`/`bv2int`,
  lines 600–605; it never emits `get-proof`, `get-model` or `set-option`), and
  `test/Target/ExportSMTLIB/basic.mlir` (piped into `z3 -in`; `REQUIRES: z3-prover`).
- `lib/Dialect/Transform/SMTExtension/SMTExtensionOps.cpp`: `transform.smt.constrain_params`
  always fails at the pin (lines 29–41; operational semantics left as a TODO).
- The Presburger library (FPL, `papers/pitchanathan-2021-fpl`, upstreamed):
  `include/mlir/Analysis/Presburger/{IntegerRelation,Simplex,PresburgerRelation,
  PresburgerSpace,Matrix,Fraction,Utils}.h` (Simplify-style simplex over an integer tableau
  with per-row common denominators, undo-log snapshots and rollback, generalized basis
  reduction for integer emptiness, lexicographic and symbolic lexicographic simplex,
  Fourier–Motzkin elimination with dark-shadow and exactness flags, GCD tightening). Numbers
  are `llvm::DynamicAPInt` (`llvm/include/llvm/ADT/DynamicAPInt.h` at the pin: an `int64_t`
  fast path with arbitrary-precision fallback per value; not vendored, outside `mlir/`).

**Not taken:** `lib/Dialect/SMT/IR/*.cpp`, `lib/Analysis/Presburger/*.cpp` (`Simplex.cpp` is
90,735 bytes, `IntegerRelation.cpp` 106,355), `Barvinok`, `GeneratingFunction`,
`QuasiPolynomial`, `PWMAFunction`, the C API and Python bindings (`mlir-c/Dialect/SMT.h`,
`mlir-c/Target/ExportSMTLIB.h`, `python/mlir/dialects/smt.py`), the unit tests
(`unittests/Analysis/Presburger/**`, `unittests/Dialect/SMT/**`). Fetch on demand with
`git -C .toolchain/llvm-project show 7208ba24ca2894729cd394475a00d2a7b605e642:mlir/<path>`.

## File manifest

19 files, 234,766 bytes in all.

```
SHA-256                                                                bytes  path
63fc2a74382de4a4ac1101d14926b42bf7a9a2d39b2c9535e439b12bcdc8e9c1        5078  include/mlir/Analysis/Presburger/Fraction.h
963a252a16a77df0dd762973c6b135bf312226d34336ff9af5697e3803a8117c       48779  include/mlir/Analysis/Presburger/IntegerRelation.h
9a1f1f302d16b26609da290c3c0d8a925a0dbcfefceabe1debf67283966311f8       15208  include/mlir/Analysis/Presburger/Matrix.h
24b7838ba442617a8857af11664b21dc020e8b8de8a08ff36e56941471d47078       11699  include/mlir/Analysis/Presburger/PresburgerRelation.h
9979ef706c6c8c54f50e3c84ac0010102a2c81f38f505b5c3b8c846ddd14a1c0       13929  include/mlir/Analysis/Presburger/PresburgerSpace.h
1c6cb18f3f65b03f2262563b98801bf5f728551145cee3caa34224c9d7eb781d       42953  include/mlir/Analysis/Presburger/Simplex.h
285e031107cdef83cf75f13730d301b4a07ff1fcee029b1934e6a076a58005ae       14661  include/mlir/Analysis/Presburger/Utils.h
229135b91d4e694b262e59a258735af916f4890d07be17e1b5dcbb0a67c2b89a         818  include/mlir/Dialect/SMT/IR/SMT.td
290dd52d03f9a919315b14cd3a83ed5d0a55ec123fee6e25413061b03e9a5423        3600  include/mlir/Dialect/SMT/IR/SMTArrayOps.td
89508f5a5c5b963826179ed64ad2fd6109e7fe7d223989cfe3b6e8d91d1f0f56        2273  include/mlir/Dialect/SMT/IR/SMTAttributes.td
75fc2c219dcd8779d4284ac8b190de07f5b2f16d56fb3a692643dd5015582a22       10100  include/mlir/Dialect/SMT/IR/SMTBitVectorOps.td
96d6ab0f70ecefb630c91497957ea8dcf709e5f49111939264bd8ed2000e3ac1         906  include/mlir/Dialect/SMT/IR/SMTDialect.td
6d45667e89f41141143e62df9e310ac860c8d74e73ed31e5a2bfe50a2e615e24        5142  include/mlir/Dialect/SMT/IR/SMTIntOps.td
97936c71596f1f140cdfe8e886773010d24604fcbafb40f876428a76341d8458       17108  include/mlir/Dialect/SMT/IR/SMTOps.td
286d41b35268a4604bf6607fd6db874303636eac6ad5f12e57652773eff6eb02        4858  include/mlir/Dialect/SMT/IR/SMTTypes.td
08d4ff7ebcda2ff8ef6b5205e4a0c8e210e3c85c13e921e6e961a7dff4dd839c        1474  include/mlir/Target/SMTLIB/ExportSMTLIB.h
9a31779be70b787e84d45882c88a8e1da533bd6a9c48c1480cd943c396e9874b        5960  lib/Dialect/Transform/SMTExtension/SMTExtensionOps.cpp
a4346590ab168ff4cba6258590fd55717d69ba90720032f202592f47d8b49bbc       25528  lib/Target/SMTLIB/ExportSMTLIB.cpp
8b895eb1063e289d8501b96b98111ca8540c69af3777b954c8f99bafcb1692ed        4692  test/Target/ExportSMTLIB/basic.mlir
```
