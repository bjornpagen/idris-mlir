# 06. Eliminating abstraction

Following Futhark and MLton, the middle end removes source-level abstraction
before MLIR sees the program. What reaches the `idr` dialect is first-order
and monomorphic (`GOAL-P2`). Each elimination here is guaranteed by profile
rules, not attempted heuristically. A program the elimination cannot handle
is rejected.

## Erasure (v0)

- **ELIM-ERASE-1 (v0).** Quantity-0 values are kept as `Erased` in `Core`
  and as `!idr.erased` in the contract. They are removed only by the 1:0 type
  conversion in `idr-lower` (`LOW-ERASE-1`). No stage before `idr-lower` drops
  an erased parameter, argument or field.
  - *Rationale:* the fact "this position is erased" stays visible and
    traceable to the source until the last stage. Removal is then one
    mechanical conversion, not a transformation spread over the pipeline.
- **ELIM-ERASE-2 (v0).** Definitions reachable only at compile time (types,
  proofs) are not translated. They stay available in `Defs` throughout
  compilation, for checks (`PROF-ESC-1`) and for proved rewrites later
  (`RW-DAY1-2`).
- **ELIM-ERASE-3 (v0).** Erasure removes only quantity-0 positions. Idris's
  additional collapsibility analysis (`safeErase`, `detagabbleBy`) is not used
  in v0 (`FE-IN-4`). A later version may adopt it as a fact, with its own rule.

## Monomorphisation (v1, planned)

The v1 revision of this document makes these rules precise. The design
constraints are fixed now.

- **ELIM-MONO-1 (v1).** Instances are created on demand from the root. An
  instance is keyed by the definition and the normal forms of those
  quantity-0 arguments that determine runtime types. Data types are
  instantiated the same way, so `Pair Int Bits8` becomes its own
  monomorphic `Data`.
- **ELIM-MONO-2 (v1).** Normalization uses Idris's normalizer after
  substitution, so type-level computation is resolved by Idris, never
  re-implemented.
- **ELIM-MONO-3 (v1).** Polymorphic recursion makes the set of instances
  infinite, as MLton notes for its own monomorphiser. The compiler MUST
  detect it: an instantiation path on which the same definition recurs with
  a strictly larger key is rejected. A hard cap on the number of instances
  backs this up. Either failure is an `unsupported` error naming the
  definition.
- **ELIM-MONO-4 (v1).** Instance names are deterministic, derived from the
  definition name and its key (`FE-DET-1`).

## Defunctionalisation (v2, planned)

Source: Hovgaard, Henriksen, Elsman, "High-performance defunctionalisation in
Futhark" (TFP 2018,
[oa-papers/hovgaard-2018-defunctionalisation](../research/sources/oa-papers/hovgaard-2018-defunctionalisation)).
Futhark restricts the typing rules so that "a conditional may not return a
function, arrays are not allowed to contain functions, and a loop may not
produce a function". Then every application's function is statically known,
and defunctionalisation specializes each application "without introducing
any branching". Records may contain functions; closures become records of
their captured values.

- **ELIM-DEFUNC-1 (v2).** The v2 profile adopts the same restrictions,
  translated to Idris:
  - no match alternative may return a function value whose static identity
    differs from that of the other alternatives;
  - no data type may hold a function at a runtime position, except
    non-recursive records whose function fields are statically known at
    every construction;
  - a recursive function may pass a function-typed argument to itself only
    unchanged.
- **ELIM-DEFUNC-2 (v2).** Each call is specialized on the static identity of
  its function-typed arguments, as in Futhark's static values and Lean's
  `fixedHO` specialization. Captured variables become extra parameters. The
  result has no function values, so no closure reaches MLIR, and the `idr`
  dialect needs no closure type (`GOAL-P4`).
- **ELIM-DEFUNC-3 (v2).** User-defined interfaces become records of methods
  (their dictionaries). They are eliminated by `ELIM-MONO-*` and
  `ELIM-DEFUNC-*` together. A dictionary that is not statically known is
  rejected.

## Forcing, detagging, collapsing (later)

Source: Brady, McBride, McKinna, "Inductive families need not store their
indices" (TYPES 2003).

- **ELIM-FORCE-1 (reserved).** Constructor arguments determined by indices,
  and constructors determined by an index (for example `Vect` with a static
  `n`, in v4), are removed from the runtime layout. This is decided in the
  frontend from TT, where the index relationships live. It is recorded as a
  fact in `Core` and in the contract, never inferred in C++.
- **ELIM-FORCE-2 (v0).** Idris's `newtypeArg` and the Nat-to-Integer
  optimization are not used. A single-constructor type already has no tag
  (`LOW-DATA-1`), which covers the newtype case, and `Nat` is not a runtime
  type.
