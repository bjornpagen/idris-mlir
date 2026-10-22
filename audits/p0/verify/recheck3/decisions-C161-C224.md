<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 3: coordinator decisions C161 to C224 against the tree

HEAD: f5736f12 at start; lanes committed during the read, and the cited
lines were read as of 70daddac to bd4dd187 (HEAD at finish). Read only:
nothing built, typechecked, generated or run. Ground for every bullet:
"read" (the cited line was opened) or "measured" (`grep`/`find`). Paths
are under `foreign/idr/` unless they start with another top-level
directory. `spec/` means `compiler/spec/IdrisMLIR/Spec/`. Owners come from
`ownership.json`.

Each decision was found by its bold label in §3 of
`proposals/0000-mlir-native.md`, with its amendments and sharpenings:
C197 sharpened, C199 amended, C210's second paragraph, C212 withdrawn,
C219 sharpened, C224 sharpened. The six hand stand-ins under
`include/idr/IR/Generated/` and the outputs not yet produced (the
`Rewrites.h.inc` behind C191, C198, C205 and C215) are not reported.

## L07

- **C192 (own.adopt only where bufferization allocates)**
  `compiler/spec/IdrisMLIR/Spec/Counting/Declarations.idr:428`: `own.adopt`
  is legal `between Higher Owned`. So the frontend's stage can still write
  it, and the Idris builder generator (`spec/Generator/Idris.idr:298`,
  `written = legalAt op.stages Higher`) gives the frontend a builder for
  it: `compiler/src/IdrisMLIR/Dialect/Idr.idr:1006-1010`, a hand print of
  that output. C192 says "The frontend writes none". Emit calls no
  `ownAdoptOp` (measured: no hit outside `Dialect/Idr.idr`), but the
  representation still allows the state C192 rules out. Bufferization runs
  at `First` (`spec/Pipeline/Pipeline.idr:306-307`), and the op's doc
  comment (`:418-421`) itself says only bufferization writes it.
  What remains: the op's legal window does not start where its one writer
  runs. (read)

## L08

- **C202 (no pass rewrites the type of a value an upstream op produces)**
  `include/idr/Analysis/Ownership/Walks.h:58-60`: `exclusivity::followed`
  shuts out a value that an upstream op *reads* (`readBare`). It does not
  shut out one an upstream op *produces*, such as a `tensor.extract` or
  `memref.load` result that holds references.
  `lib/Transforms/Ownership/Exclusive.cpp:76-82` (`writeVersion`) then
  calls `setType(... Unique::Deep)` on every followed value the solve marks
  exclusive. The header comment (`:7-8`) states only the "reads" half.
  The in-place rule and idr-unique-results do keep C202
  (`lib/Transforms/InPlace/Chains.cpp:140-146`,
  `UniqueResults.cpp:279-280`). What remains: idr-rc-exclusive's filter
  does not make C202's state unrepresentable. I did not check whether the
  solve can in fact prove such a value exclusive. (read)
- **C178 (program-sized state in the footprint vocabulary)**
  `lib/Transforms/InPlace/Unique.cpp:218` and
  `lib/Transforms/InPlace/UniqueResults.cpp:207`: the body's numbering is
  an `llvm::DenseMap<Value, Local>`, one entry per body value. It is
  outside the footprint allocators, so no pass footprint counts it, and it
  is the pointer-keyed per-node map AGENTS.md forbids. (measured)

## L02

- **C178** `lib/Transforms/Effects/Writer.cpp:87-88`: `std::vector`
  `writable(graph.size().value(), 0)` and `owners`, sized by the program
  graph. Also `Effects/Component.cpp:96-97` and `Effects/Parts.cpp:52`
  (`std::vector<WriteNode> seeds`). This is a solver's program-sized state
  outside `footprint::Vector`, so the per-pass footprint (C178's scale
  measure) leaves it out. (measured)

## L09

- **C178** `lib/Transforms/Joins/IdenticalRegions.cpp:43`:
  `llvm::DenseMap<Value, unsigned> number` per region compared. It is
  pointer-keyed, uncounted state, sized by the region. (measured)

## L10

- **C206 (the tail decider looks through a free reindex)**
  `lib/IR/Tail.cpp:27-31`: `carriesOn` is `dyn_cast<DataReindexOp>` and
  then `hasTrait<ResultCarriesOperand>`. That is an op test beside a trait
  test over the same question, a two-arm ladder over ops, where AGENTS.md
  asks for MLIR dispatch (an interface or a trait). C206 itself fixes only
  the behaviour, and the behaviour is in place (`DataReindexOp::isFree`,
  `lib/IR/Families/Refinement.cpp:87-90`). (read)

## L12

- **C178** `lib/Transforms/StructureLoops/Linalg.cpp:41`:
  `DenseMap<std::pair<Value, AffineMap>, unsigned> numbered`. It is
  uncounted and pointer-keyed. (measured)

## L16

- **D68 growth proof (C219, C221, C222, C223, C224)**: in progress.
- **C213 and C217 (refused only where the set or the use types are
  unbounded)** `compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr:452`
  refuses `RuntimeClosure` with "a function computed at run time, applied
  inside a settled term that settles it again". `:805` refuses with "a form
  whose type its body does not give, applied inside a settled term". Each
  message names a situation of the translation, not a member set or
  use-type set that no analysis bounds. C213 and C217 allow only the
  unbounded case, and AGENTS.md has the refusal name "the value whose set
  is unbounded". The other two sites name either a growth case
  (`Terms.idr:944`, a value computed inside another of its own) or a field
  that is no implementation (`Translate/Cases.idr:735`). What remains:
  either show that the two sites at `:452` and `:805` are unbounded and say
  so in their messages, or compile them. (read)

## L18

- **C178** Per-function and per-wave state in `llvm::DenseMap`, outside
  the footprint vocabulary (measured):
  - `lib/Transforms/Optimize/Contify.cpp:177` (`groups`, by function);
  - `Optimize/Settle.cpp:257` and `Optimize/Waves.cpp:63`;
  - `Specialize/Order.cpp:189-190` (`known`, `sizes`);
  - `Deduplicate/Deduplicate.cpp:153-154`;
  - `Optimize/Captures.cpp:81`;
  - `Optimize/CaptureDrops.cpp:163`;
  - `Defunctionalize/Declare.cpp:106`.

## L19

- **C197 (the guard comes from the specification's op)**
  `harness/Prims.idr:413-416`: the oracle finds each guard op's
  `Condition` by its mnemonic in a list of pairs. `:445-447` looks that
  mnemonic up and has a run-time `Left "... has no reading in the oracle"`
  branch. The guard op is identified by its printed name, and an unread
  guard is an error at run time rather than a missing case. The
  `Condition` meaning is the oracle's own, as C197 allows; the lookup by
  name is what remains. (read)
- **C178** `lib/Transforms/Expect/LabelsLeast.cpp:119-123`: per-point
  `std::vector`s (`edges`, `held`, `runsAt`, `firings`) outside the
  footprint allocators. (measured)

## INT, with L11 (needs stage 1)

- **C201 (the tools' stacks plus the outside-code margin, measured per
  target)** `CMakeLists.txt:216-222` refuses to configure until
  `IDRIS_MLIR_TOOL_STACK_BYTES`, `IDRIS_MLIR_TOOL_SIGNAL_BYTES` and
  `IDRIS_MLIR_OUTSIDE_STACK_BYTES` are given. All four target entries still
  call `idris_mlir_unmeasured_stacks()` (`:262`, `:279`, `:297`, `:330`).
  None records a measured number with its build and input. The mechanism
  is in place: `runtime/Start/Runner.cpp` adds the margin, and
  `include/idr/Driver/Tool.h:45-49` requires the sizes. What remains: the
  measurement (D56). (read)

## Coordinator

- **C213, text against code**: C213 names two frontend refusals, `runtime
  closure` and `static argument`. The specification has no `static
  argument` rule (absent: `grep -n StaticArgument
  compiler/spec/IdrisMLIR/Spec/Core/Rules.idr`; 52ec023e removed it
  because "nothing in the frontend refuses with it"). Either the text
  names a refusal that no longer exists, or the code dropped one that C213
  expects. (measured)
- Owner questions, not lane work: the claim `LArray`'s buffer needs
  (C193, §4's open item), and resolution as an interval join (C216's
  second half, §4's fourth question).

## Done

64 decisions checked (C161 to C224). 51 are done in the tree, among them:

- C212's withdrawal, carried out: one `Fin` index, and `allFins` built
  once in `Core/Termination/SizeChange.idr:447-451`;
- C199 as amended: knowngen check in `make check`, `Makefile:362-365`;
  no manifest entry;
- C197 as sharpened: the Idris-level types are the table's own;
- C210's switch: `lib/Driver/Main.cpp:96`, given last;
- C216's first half: the flat parse tree, 499cbacf; no `PApp`/`PRef`
  built in `Idris/Parser.idr`.

13 are not fully done: C178, C192, C197, C201, C202, C206, C213, C217,
and the five growth decisions (C219, C221, C222, C223, C224).
