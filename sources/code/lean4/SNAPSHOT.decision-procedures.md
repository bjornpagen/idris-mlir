# Snapshot addendum: Lean 4 decision procedures with certificates (`decide`, `native_decide`, `omega`, `bv_decide`)

Addendum to `code/lean4/SNAPSHOT.md` (staged by the dependent-equality cluster of this pass at
the same revision, with the `LICENSE` and `src/Init/Tactics.lean`, which holds the user-facing
docstrings of `omega` and `decide`; neither is stored twice); merge it there. Written by the
decision-procedures cluster of the 2026-10-09 pass.

- **Upstream:** `leanprover/lean4` on GitHub.
- **Revision:** `7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f`, the HEAD the other clusters of this
  pass pinned (resolved with `git ls-remote` on 2026-10-09; the tree was listed with
  `https://api.github.com/repos/leanprover/lean4/git/trees/7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f?recursive=1`).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/leanprover/lean4/7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f/<path>`.
- **Paths:** relative to the repository root.
- **Licence:** Apache-2.0 (each file's header says the same).
- **Threads:** decision-procedures (Fast dependent type checking and elaboration).

**What is here and why.** How Lean turns a decision procedure's answer into something its
kernel accepts, and what each route trusts:
- `src/Lean/Meta/Native.lean` (`nativeEqTrue`, lines 30–87): compile a closed `Bool`, run it,
  and add an *axiom* `e = true`; the basis of `native_decide` and `bv_decide`.
- `src/Lean/Elab/Tactic/Decide.lean` (`evalDecideCore`, lines 83–195): `decide` by elaborator
  reduction, `+kernel` by a cached auxiliary lemma checked once by the kernel, `+native` by
  `nativeEqTrue`; failure diagnosis (stuck on `Eq.rec` or `Classical.choice`).
- `bv_decide`: `src/Lean/Elab/Tactic/BVDecide.lean` (module documentation, lines 19–90: options,
  the eight-step architecture, and the statement that the compiled check adds the Lean compiler
  to the trusted code base), `src/Lean/Meta/Tactic/BVDecide/Main.lean`,
  `Prover/Basic.lean`, `Prover/Bitblast.lean` (`LratCert.toReflectionProof`, lines 24–45: the
  certificate becomes a compiled `String` constant, `verifyBVExpr expr cert` is run natively,
  the axiom closes the goal; counterexample reconstruction, lines 101–112),
  `Reflect/Basic.lean` (reification), `External.lean` (calling CaDiCaL with a wall-clock timeout
  implemented in Lean, lines 93–145 and 206–220), `LRAT/Cert.lean` and `LRAT/Trim.lean` (the
  trimming algorithm of `papers/pollitt-2023-lrat-cadical`, section 4).
- The verified side in `Std`: `src/Std/Tactic/BVDecide.lean`, `Std/Tactic/BVDecide/Reflect.lean`
  (`verifyCert`, `verifyCert_correct`, `verifyBVExpr`, `unsat_of_verifyBVExpr_eq_true`, lines
  171–200), `Std/Tactic/BVDecide/LRAT/{Actions,Checker}.lean`,
  `LRAT/Internal/Checker.lean` (the checker loop and `unsat_of_check`, lines 21–85),
  `LRAT/Internal/Rup.lean` (RUP hint propagation), `src/Std/Sat/AIG/Basic.lean` (the
  hash-consed and-inverter graph: `Fanin` packs the inverter bit into the low bit of a `Nat`,
  and `Cache.WF` is the invariant of the structural-sharing cache, lines 110–200).
- `omega`: `src/Lean/Elab/Tactic/Omega.lean` (module documentation: Pugh's omega test without
  dark and grey shadows, so incomplete; preprocessing; balanced-mod equality solving;
  Fourier–Motzkin real shadow; lazy disjunction splitting), `Omega/Core.lean`
  (`Justification`, lines 34–126: each derived constraint carries a proof recipe that is
  turned into a proof term only after a contradiction is found), `Omega/Frontend.lean`,
  `Omega/OmegaM.lean` (atoms up to defeq and the facts generated per new atom).

**Shared with the elaborators cluster.** That cluster read several of these files and
recorded them in `code/lean4/SNAPSHOT.elaborators.md`; they were staged once, here.

**Not taken:** the `bv_normalize` simp set (`src/Lean/Meta/Tactic/BVDecide/Normalize/**`,
including the 68 KB `Simproc.lean`), the bitblaster circuits and their proofs
(`src/Std/Tactic/BVDecide/Bitblast/**`), the CNF and AIG-to-CNF modules (`src/Std/Sat/CNF/**`,
`src/Std/Sat/AIG/CNF.lean`), the RAT checker (`LRAT/Internal/Rat.lean`, fetched for reading,
not stored), the LRAT parser, `Init/Omega/**` (the proved arithmetic lemmas), `grind`. Same
raw URL pattern. Nothing was built or run.

## File manifest

The files this addendum adds, computed 2026-10-09 over the stored copies (`shasum -a 256 <path>`
from `code/lean4/`): 21 files, 187,935 bytes in all.

```
SHA-256                                                                bytes  path
353a86ba106ab2919f017e9350a2c0f1e7b54d87747ccf7943559078e0a8d6cd       12601  src/Lean/Elab/Tactic/BVDecide.lean
6773f54ca73ee7405a91c5ffb3b827db4ecdbb22b28a494cf5e2fe8ac224c4b3        9747  src/Lean/Elab/Tactic/Decide.lean
7a81cef2ff724f9f690993d01aef906b200ca11c36f72fb57f9e6e5eaf4ec45e        9449  src/Lean/Elab/Tactic/Omega.lean
0cc1a59420d93bc08bd167066df6f2ffb5e1a13d75cf28937faddf0d83925c87       21501  src/Lean/Elab/Tactic/Omega/Core.lean
46ded66aa93b44f34c4f95efba3a01373ac45834a3828c7171e21acffbec02a4       30256  src/Lean/Elab/Tactic/Omega/Frontend.lean
b0970ff3adb9c0ad57a888134f1fa317580fc2b3412c27addcae3df2e70055b3       11078  src/Lean/Elab/Tactic/Omega/OmegaM.lean
e1d0c6b5be42f492810a12281fc0d8ff4c981e421397c3ec00e165a255ed09c1        3207  src/Lean/Meta/Native.lean
a2d3883ccfe4e75489a7164c8ab10b3ad18277e9eba46457940d95d344af02a5        7900  src/Lean/Meta/Tactic/BVDecide/External.lean
a0eea966a1ec6f6fe932d8a28902b22dca82175ffd7e579832b0f3370cbb8641        4090  src/Lean/Meta/Tactic/BVDecide/LRAT/Cert.lean
10cd3006821ab58d14ba580c28e3efd173d72ed02ab3e87136784943924f32ef        8831  src/Lean/Meta/Tactic/BVDecide/LRAT/Trim.lean
7dc7f2ad7e984c58bf523e649bd59150be368e87e899c3a43806df71fd6b2812        1937  src/Lean/Meta/Tactic/BVDecide/Main.lean
4b0e86556f296ece47b39f00f55a82b0774ca43545868e4c8caaa83c95fbeeed        2807  src/Lean/Meta/Tactic/BVDecide/Prover/Basic.lean
658f161d5937739b83bf566a002e83692e25002c39f0fc993534659369ca5cf4        4785  src/Lean/Meta/Tactic/BVDecide/Prover/Bitblast.lean
742be07bfdc04dcba991654f372ac639f11084436390a6dfd07d954fb5c99387       17011  src/Lean/Meta/Tactic/BVDecide/Reflect/Basic.lean
e85353dcc03360bcc31942c775acbbb6607697659052b5506838798960ac48fb       20504  src/Std/Sat/AIG/Basic.lean
29b6e1d53af49491ed0e03d35a161f19830eec02aaea899ba49133cd5bd60f6c         585  src/Std/Tactic/BVDecide.lean
68f710eb7c0d7464606e6dbf3a708b820e9b41bcf29b90ded5e94079c3cc4721        1734  src/Std/Tactic/BVDecide/LRAT/Actions.lean
7aea1fe3901a9b2a2c93abf3f8867d6e9045183ff01a4c8a7c3378b3720ae702         938  src/Std/Tactic/BVDecide/LRAT/Checker.lean
cf12384e35da70c02cc91d0bcddebd62923dd0ad4db78b76b90bede5b346a0a1        2802  src/Std/Tactic/BVDecide/LRAT/Internal/Checker.lean
04b13f3829cb841de2cc2786946ff7fed91785ed6d8187a219dfb95bfa2fbd63        9666  src/Std/Tactic/BVDecide/LRAT/Internal/Rup.lean
912d52f783dde28ca43460dbd6a0bc009c0c4276b674ef0b816eba6dbba60650        6506  src/Std/Tactic/BVDecide/Reflect.lean
```
