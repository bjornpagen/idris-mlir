<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 3: coordinator decisions C81 to C160 against the tree

HEAD at start: f5736f12. HEAD at finish: eb62301c. The seven commits in
between touch none of the files cited below except `Frontend/Growth/*`,
which is L16's growth work and is not detailed here. Nothing was built
or run. Ground: **read** means the cited line was opened; **measured**
means a `git grep -P` or `find` count over the tracked tree. Amendments
read with their decisions: C85 by C208, C113 by C204, D98 and C158, C119
by C195, C134 by C197, C138 by C177, C140 by D93 and C160, C149 by C163
and C165. Paths are under `foreign/idr/` unless they start with another
top-level directory; `spec/` means `compiler/spec/IdrisMLIR/Spec/`.

## L03

- **C116 (decide/apply pairing)** `spec/Pipeline/Pass.idr:42,145-166`,
  `spec/Pipeline/Pipeline.idr:540-546`. `PassKind` has a `Decide` case,
  but no pass in `passes` uses it (measured: `git grep -P '\bDecide\b'`
  finds only the declaration). The `Pass` record has no field that names
  an apply step's decide step. C116 says "each apply group is paired with
  its decide step in the pipeline's record"; the record holds no such
  pairing. (read, measured)
- **C144 (no undecided hold)** `spec/Pipeline/Stage.idr:83-85,114-122,167-170`.
  The stage table still has `StageHolds = HoldsUndecided | HoldsDecided`,
  printed as `Undecided` ("a hold may still be strengthened before
  counting"). C144 says "No hold is ever undecided … the grade has no
  undecided case and no meaning that depends on the stage". The
  strengthening C144 allows has no name in the table, and "undecided"
  stays as a stage fact. Two C++ readers depend on it; they are listed
  under L09 and L12. (read)
- **C156 (B measured)** `spec/Pipeline/Pipeline.idr:278-285`. `nodesPerOp
  = 64` says "Not yet measured". The stage-1 measurement is still owed,
  shared with L14. (read)

## L06

- **C99 (upstream recursions)** `PINS.md:546-553`. Some recursions are
  "left, for the stage-1 stack painting to measure": the op parser and
  printer, a dialect attribute's parser and printer, and `eraseOp`
  through a `std::function`. C99 lists the printer and the parser among
  the families that get one patch each. Those patches wait on the
  painting, which needs stage 1. (read)

## L09

- **C109 (world renamed mutable)** `include/idr/IR/FlowEdges.h:266-268`.
  The comment still says "an edge of a word or of a world is never
  declared". Under C109 no world reaches the C++, so this is stale
  vocabulary. (read)
- **C144 reader** `lib/Transforms/Joins/YieldedFields.cpp:57-62,76`.
  `holdsUndecided` reads `StageHolds::Undecided` to gate the rule. It
  lives or goes with the L03 row above. (read)
- **C120 (a choice is a sum, never a bool)** `include/idr/Transforms/Joins/Rules.h:54-55`,
  `lib/Transforms/Joins/Rules.cpp:120-122`. `rewriteIf(bool holds)` takes
  the rule's choice as a `bool`. It has nine callers in `JoinRules.cpp`
  and `MatchRules.cpp`. This is the same shape as `foldCheck(…, bool
  holds)`, which C120 deletes. (read, measured)

## L11

- **C101 (`idris_rt_exit(uint8_t)`)** `runtime/End/End.cpp:319-325`.
  `idris_rt_exit(int64_t status)` casts to `uint8_t` inside. The
  specification's ABI row agrees with the runtime: `CallsRuntime
  (MkRuntimeCall "exit" [TakesInt64] NeverReturns)` (`spec/Ops/IO.idr:161`,
  L13). C101 names `idris_rt_exit(uint8_t)`, so the type would carry the
  0-to-255 fact that the guard before it establishes. The code and the
  decision disagree on the signature. (read)
- **C110 (where the domain header lives)** `runtime/Big/Arithmetic.cpp:7-8`.
  The runtime includes `idr/IR/Numeric/Inline.h` and `Small.h` from
  `foreign/idr/include`, together with that header's
  `idr/IR/Generated/NumericEnums.h.inc` (`include/idr/IR/Numeric/Domain.h:24-31`).
  C110 puts the freestanding word "in a freestanding header under
  `runtime/`". The template is freestanding and shared as AGENTS.md
  asks; only its place differs from C110's text. Both sides are reported
  so the coordinator can settle which governs. Shared with L13. (read)

## L12

- **C107 (element take: no test, no free-then-allocate)** `lib/Conversion/Elements.cpp:109-134`.
  `takeOut` still makes a run-time `runtime.isUnique` test on a boxed
  element's cell (`:125`). On the shared path it adds an `inc`, a `dec`
  and a fresh `allocate` in the lowering (`:128-132`). It skips them only
  where the array claims `unique deep` (`boxSharingOf`, `:109-111`). C107
  deletes "the element take's test and free-then-allocate" and says "an
  element update reuses its cell at the `idr` level". The code comment
  (`:123-124`) says sharing "is known only here, at run time", so the
  code's reason and the decision disagree. (read)
- **C144 reader** `lib/IR/OpsArrayFusion.cpp:78-84,93`. `uncounted` is
  documented as "counts no reference yet: its holds are undecided", but
  it reads `holdsAt[...] == StageHolds::Undecided`, not `countingAt`.
  The generated table gives Graded holds `Decided` and counting
  `Uncounted` (`spec/Pipeline/Stage.idr:167-176`), so at Graded the
  function's name and the column it reads give different answers. The
  vocabulary goes with the L03 row; the column choice needs this lane to
  look at it. (read)
- **C116 reader** `lib/Transforms/Narrow/Narrow.cpp:86-93`.
  `idr-narrow-words` reads its decision with its own
  `getCachedParentAnalysis<Ranges>` and a hand-written internal error.
  It does not use `solver::decided` (`include/idr/Analysis/Solver/Decision.h:43-49`),
  which is meant to be the one form of "a missing decision an internal
  error". (read)

## L13

- **C111 (a guard's condition is a D41 function)** `lib/IR/OpsChecks.cpp:59-69`,
  `lib/Conversion/Checks.cpp:74-87`. The non-empty-string condition and
  the finite-double condition are not functions of the numeric template.
  Each is written once in the folder (`nonempty`, `finite`) and again in
  the lowering (`arith.cmpi eq length, 0`; `math.isfinite` xor true). So
  two guards still state their condition twice. `Nonzero`, `InBounds` and
  `InRange` do read the template (`Checks.cpp:48-50,70-71,102-104`).
  (read)
- **C120 (bool choices)** `lib/IR/OpsChecks.cpp:38`. `known(bool holds)`
  turns a `bool` into `numeric::Known`, the `foldCheck(…, bool holds)`
  shape C120 deletes. Its callers pass `bool` predicates (`:62,68`).
  (read)
- **C113/C158 (op name)** `spec/Ops/Values.idr:7`. The module doc says
  the op is `idr.target.os`, but it is declared `platform.os` (`:198`),
  which is the name the mnemonics contract fixes. The doc line is stale.
  (read)
- **C110** see L11 (the header's place and the runtime's include).
- **C101** see L11 (`spec/Ops/IO.idr:161`, `TakesInt64`).

## L14

- **C116 (decide step's const view)** `include/idr/Analysis/Solver/Decision.h:13-16,43-49`.
  The header says "The pipeline's record pairs each apply step with its
  decide step", but the record does not (L03 row). `solver::decided`
  has no caller (measured: its only hit is its definition), and only
  `Ranges` declares a `decideStep` (`include/idr/Analysis/Ranges.h:53`).
  So the helper is dead code and the comment states something the tree
  does not do. (read, measured)
- **C109 (world renamed mutable)** `include/idr/Analysis/Solver/TypeGraph.h:34-35`.
  The comment still says "an array a world orders". This is stale
  vocabulary for `#idr.mutable` memory. (read)
- **C156** see L03 (`nodesPerOp`, stage 1).

## L16

- **C82 (impossible arm kept with its justification)** `compiler/src/IdrisMLIR/Term.idr:210-211`,
  `compiler/src/IdrisMLIR/Frontend/Translate/Cases.idr:250-253,272-276`.
  An arm Idris proved impossible is `Dead` and "left out of the match".
  `Unreachable : Loc -> Term n` is written only when no arm is possible,
  and it carries a location, not a justification. C82 says "an arm Idris
  proved impossible stays as an `unreachable` carrying its justification,
  an essential branch". The code and the decision disagree. (read)
- **C122 (one position type)** `compiler/src/IdrisMLIR/Frontend/Translate/State.idr:427-433`,
  `compiler/src/IdrisMLIR/Frontend/Resolve.idr:246-253`,
  `compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr:331-336`.
  - C122 fixes a position as `Absent | Index Sort | Runtime Quantity
    ClosedTerm`. The code has `ArgumentAt = NoValue | RuntimeValue Uses`,
    and leaves the index case to each instance (`IndexParam`).
  - The same fact is held a second time in `Use = Erased | Used Uses`
    (Resolve.idr). `byQuantity` maps one onto the other case for case,
    so the frontend holds two copies of one fact.
  - Erasure itself is read once, from the fork's `eraseArgs`
    (`Closed.idr:338-350`), as C122 and `upstream/fork-erase-args`
    state. That part is done.
  (read)
- **C123** is in progress, part of the D68 growth proof (L16).

## L17

- **C126 (term comparison with stock Idris)** absent:
  `git grep -nliP 'ambiguity|checked term|stock Idris' -- tests tools harness`
  finds no comparison of checked terms at `%ambiguity_depth 1000`. The
  elaboration itself is in place (`ITypeOrValue`, `Overlaid`,
  `compiler/idris/src/Idris/Desugar.idr:571-589`; `Sort = Universe |
  Known | Unknown`, `compiler/idris/src/TTImp/Elab/Ambiguity.idr:478-485`).
  The check is still to be written, with L19 for `tests/`, and run once
  there is a build. (measured, read)
- **C127 (one search sum; quote result)**
  - `compiler/idris/src/Core/Unify.idr:186-188` declares `Searched =
    Found a | Grows Grown`. C127 says `Found | Repeated | Grown`. In the
    code a repeated goal fails its step "as upstream's cycle"
    (`compiler/idris/src/Core/AutoSearch.idr:696-708`) instead of being a
    case of the sum. The code and the decision disagree.
  - The quote's interface does return `Quoted | TooDeep`
    (`compiler/idris/src/Core/Normalise/Quote.idr:28-30`). But the depth
    still travels as the `Error` constructor `QuoteTooDeep`
    (`compiler/idris/src/Core/Core.idr:202-204`), thrown at
    `Quote.idr:200` and caught at `:58-66`. That constructor keeps show,
    location, equality and `perror` arms for an error the source says is
    "never reported" (`Core.idr:413,533,624`;
    `compiler/idris/src/Idris/Error.idr:120,760`).
  (read)

## INT

- **C98 (margin measured per target)** `CMakeLists.txt:177-224`. Every
  target entry still calls `idris_mlir_unmeasured_stacks()`, so the
  outside-code margin and the tools' stacks are not recorded. The
  measurement is owed at stage 1, with L11; C201 settles the margin. The
  stack bound itself is in place: `DiagnosticInfoStackSize` in
  `lib/Driver/StackBound.cpp:56`, and the record `idris_rt_program_built`
  in `runtime/Start/Entry.cpp:36-44`. (read)

## Count

80 decisions checked (C81 to C160, with the amendments listed above).
- 63 found done in the live tree.
- 17 have findings above: C82, C98, C99, C101, C107, C109, C110, C111,
  C113/C158, C116, C120, C122, C123 (in progress), C126, C127, C144 and
  C156.
- Of those 17, three are measurements that need stage 1: C98, C99 and
  C156.
- Several rows recheck2 left open are closed now:
  - The stale CMake sources: 0 listed sources are missing, measured over
    `lib/CMakeLists.txt` and `lib/*/CMakeLists.txt`.
  - The `Linear.cpp` comment of C173 has been rewritten.
  - The function maps keyed by name in Contify and Deduplicate are gone.
