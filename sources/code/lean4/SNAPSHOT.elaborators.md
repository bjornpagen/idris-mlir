# Snapshot addendum: Lean 4 kernel, caches, sharing, defeq, instances, parallel driver

Addendum to `code/lean4/SNAPSHOT.md` (whose `LICENSE` and revision this shares); merge it
there. Written by the elaborators cluster of the 2026-10-09 pass.

- **Upstream:** `leanprover/lean4` on GitHub.
- **Revision:** `7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f`, the same HEAD the other clusters
  of this pass pinned (resolved again with `git ls-remote` on 2026-10-09; a file staged by
  another cluster was re-fetched at this revision and compared byte-identical with `cmp`).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/leanprover/lean4/7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f/<path>`.
- **Licence:** Apache-2.0 (`LICENSE` was fetched and is byte-identical to the copy already
  staged under `code/lean4/`; not stored twice).
- **Threads:** elaborators (Fast dependent type checking and elaboration).

**What is here and why.**
- Kernel (C++): `src/kernel/type_checker.h` (the per-checker state: two infer caches, the
  `whnf_core`, `whnf` and unfold caches, and positive/negative `is_def_eq` pair sets with the
  comment, lines 33–41, on why no union-find closure is taken), `src/kernel/type_checker.cpp`
  (`infer_type_core` 325, `whnf_core` 464, `whnf` 702, `quick_is_def_eq` 798,
  `lazy_delta_reduction_step` 962, `lazy_delta_reduction` 1051, `is_def_eq_core` 1128,
  `is_def_eq` 1205), `src/kernel/instantiate.{h,cpp}` (skips subterms by loose-bvar range),
  `src/kernel/replace_fn.cpp` (traversal cache keyed by pointer and binder offset, used only
  for nodes whose reference count says they may be shared), `src/kernel/expr.{h,cpp}` (the
  64-bit cached data word: hash, flags, loose-bvar range; `is_likely_unshared` 361),
  `src/kernel/expr_eq_fn.cpp`, `src/kernel/abstract.cpp`, `src/kernel/environment.cpp`.
- Sharing: `src/runtime/sharecommon.{h,cpp}` (hash-consing pass `sharecommon_quick_fn`).
- Metavariables: `src/library/instantiate_mvars.cpp` (two-pass linear-time
  `instantiateMVars` with delayed assignments; header comment).
- Elaborator (Lean): `src/Lean/Meta/ExprDefEq.lean` (pattern-unification conditions and the
  approximations A1–A7 from line 807, `isDefEqDelta` heuristics 1–11 at 1850, the
  transient/permanent defeq caches 2438–2480, `isExprDefEqAuxImpl` 2489),
  `src/Lean/Meta/WHNF.lean` (whnf cache only for closed, metavariable-free terms, 1039),
  `src/Lean/Meta/SynthInstance.lean` (tabled resolution: generator/consumer nodes 50–66,
  `mkTableKey` 165, the table and stacks 191, `addAnswer` 474, `consume` 543, `resume` 644;
  heartbeat and size limits at the top).
- Driver: `src/Lean/Language/Lean.lean` (notes on incremental parsing and on incremental
  command elaboration with promise-backed snapshot trees; the parsing cost figure at lines
  30–31), `src/Lean/Elab/Frontend.lean`.

**Not taken:** `Lean/Meta/DiscrTree.lean` at this revision is a 356-byte re-export; the
implementation moved and was not chased. `Lean/Meta/Basic.lean` (136 KB, the cache records),
`InferType.lean`, `Instances.lean`, the compiler. Nothing was built or run.

## File manifest

The files this addendum adds: 18 files, 485,441 bytes in all.

```
SHA-256                                                               bytes  path
623d22758bdda950ad706bda028c482356b909af9b462a398bcc195707399a56      19897  src/Lean/Elab/Frontend.lean
bba6c18e26f5aec20dfebf8d7a5095be3b52e1d3f6e8464befd9d81498241dec      43970  src/Lean/Language/Lean.lean
9dab114696644a663e325b7d65453635d1f45ffae18739abb87b357dd3f58d05     116251  src/Lean/Meta/ExprDefEq.lean
d09fa49878c8fa82d7b69fed0783f818cd29c8366ab57a7c39b6a3a25eb40d67      69135  src/Lean/Meta/SynthInstance.lean
9e964b8a7eeed5f75237bf3351226b2f5f10c338d3445a125a078d7c2c468703      45803  src/Lean/Meta/WHNF.lean
b88c8b1a7243be149fc6ea3f13be42a276d68331055e15aeaacf863e24879f79       2725  src/kernel/abstract.cpp
1b0c7b40e239f503031eba3512cfa1bcc776c0136797f92ba2e7fbd68ba6e2da      12182  src/kernel/environment.cpp
1efcadbb18cdc39722299b867851ca42be0e61811be70c0b84880dedf588b1d2      16561  src/kernel/expr.cpp
f62deffe5dbab22a915bcf87833d984139527691b4ebcebfb60f734da1265227      21255  src/kernel/expr.h
8f7d83a89a8e18f4f3939e60118bc56c843102b2d1c14f3ce617312403c7f368       5142  src/kernel/expr_eq_fn.cpp
a77dcf56be65a6f8a2f7ede7eff9f2b0665e965667b8ceaf976190f34c6b5b2d      10369  src/kernel/instantiate.cpp
f074c9054189cbbca4008938d3f42969a7d04e97218e60909be64c7108887bff       1980  src/kernel/instantiate.h
2edfa1721059dbb570ba99746f2cd60d1d691071523c129a12b3b9414972ac67       5574  src/kernel/replace_fn.cpp
c6e8c2e7aa6d76efcc7b6d79cc8030496ab084de212c7e224cd3d655f38edc8e      50381  src/kernel/type_checker.cpp
9168a759590e772e71fc1a4c854ad78641f45c9a0e2472b8cb9361598d9ac133       8505  src/kernel/type_checker.h
c21ebc62ffb5c29f26aacdb7cdb8285578e8090a220d358278e7a10fb191b70f      36078  src/library/instantiate_mvars.cpp
2726b9384e4bbfe078983d1c62438bedd622c18aacf0196c24d3d397acadb622      17285  src/runtime/sharecommon.cpp
f84596bdc8e58b4c3df436f7ff3eaf0f07accd74a9b335d66937fc1261d1e60e       2348  src/runtime/sharecommon.h
```
