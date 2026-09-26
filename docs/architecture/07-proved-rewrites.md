# 07. Proved rewrites (reserved)

**Status: future.** No profile version includes this feature, and no code
for it is written until a version adopts it (D8). This document records the
intended design and the obligations that apply from day one, so that nothing
built now closes the door.

## The idea

A developer writes a clear specification `f` and a faster implementation
`g`, and proves in Idris that they agree. The compiler then compiles calls to
`f` as calls to `g`. This is not superoptimization: nothing is searched
for or synthesized, and every replacement is justified by a proof the
developer wrote and Idris checked.

## Prior art

- **Lean 4 `@[csimp]`** (`src/Lean/Compiler/CSimpAttr.lean`, lean4 at
  `fcecee3`). A theorem `@f = @g` lets the compiler replace `f` by `g` "in
  compiled code, but not in the type theory". Lean calls it "a safer
  alternative to `@[implemented_by]`", and warns that "it is still possible
  to register unsound `@[csimp]` lemmas by using `unsafe` or unsound axioms
  (like `sorryAx`)". Lean applies such replacements before specialization,
  "to ensure we specialize the replacement" (`LCNF/Passes.lean`).
- **Idris 2 `%transform`** (`src/Core/Transform.idr`,
  `src/TTImp/ProcessTransform.idr`). The rule's two sides are only type
  checked; no equality is proved. It is applied when the runtime case tree is
  built (`applyTransforms` in `ProcessDef.idr`), so it affects `treeRT` only.

## Rules that bind now

- **RW-DAY1-1 (v0).** The middle end's pass order reserves the `Rewrite`
  position, before monomorphisation and defunctionalisation (`CORE-PASS-1`).
- **RW-DAY1-2 (v0).** The compiler never discards compile-time-only
  definitions, or their bodies and types, before the middle end has run
  (`ELIM-ERASE-2`). A proof is quantity 0, and is still a fact the compiler
  can read.
- **RW-DAY1-3 (v0).** The escape-hatch audit (`PROF-ESC-1`) is a reusable
  function over the transitive references of any set of definitions, not
  code tied to `main`. It is the future proof audit.
- **RW-DAY1-4 (v0).** `%transform` has no effect on this compiler, because
  the compiler reads `treeCT` and never `treeRT`. It is also a pragma, so
  profile programs cannot contain it (`PROF-PRAG-1`).

## Constraints on the future design

When this feature is adopted, the design MUST satisfy the following:

- **RW-FUT-1.** No pragma. A rewrite is declared by an ordinary Idris
  definition whose type the compiler recognizes, for example a value of a
  small library type that holds the proof at quantity 0. The exact surface is
  open question 4.
- **RW-FUT-2.** Pointwise equality. Idris has no function extensionality, so a
  rule proves `(x : a) -> f x = g x`, and multi-argument functions curry. A
  precondition is expressed in the domain type, for example `Fin n` or a
  quantity-0 proof argument. The call site already carries that evidence, so
  no proof search happens at compile time.
- **RW-FUT-3.** The proof, and every definition it transitively refers to,
  passes `PROF-ESC-1`, and Idris's totality checker reports it total.
- **RW-FUT-4.** `f` and `g` are both covering and pure (no `%World`) and in
  the profile. `g` terminates wherever `f` does. The simplest sufficient
  condition is that both are total.
- **RW-FUT-5.** The replacement relation is acyclic, and each `f` has at most
  one replacement.
- **RW-FUT-6.** Rewriting happens in the middle end at the reserved position,
  over the whole program, including library code. MLIR never sees rules or
  proofs; it sees only `g`.

## Known limits

- Idris cannot prove equations about primitive arithmetic on variables
  without axioms, because primitives do not reduce on variables. Rules
  therefore apply mainly to data-level code (user data types, and `Nat`,
  lists, `Fin` once they are in the profile). A trusted set of axioms about
  primitives would be a separate decision.
- In the heap-free profile there is little data-level code to rewrite. The
  feature becomes valuable once recursive data exists.
