# U02 — The cycle check, the linearity verifier's sentinel, idr-canonicalize on upstream's pass

Mandatory findings: F-prom-1 F-own-5 F-poison-7

## Permitted outcome

1. **The cycle check.** The `idr.program` verifier rejects a mutable
   cell whose type can reach itself, with
   `unsupported (cycle): ...` naming every type on the cycle (C10.1).
   Mandatory.
2. **The linearity verifier's sentinel.** `IDR/Verify/Linearity.cppm`
   uses no `ub.poison` as a C++ sentinel (C2.4). Mandatory.
3. **`idr-canonicalize`.** It is built from upstream's
   `createCanonicalizerPass(GreedyRewriteConfig, ...)` with a listener
   that keeps today's per-pattern counts, instead of copying
   canonicalize's options. Mandatory.

## Owner / exclusive writes

- `IDR/Verify` (new `Cycles.cppm`, `Program.cppm`, `Linearity.cppm`,
  `Verify.cppm`, `CMakeLists.txt`)
- `IDR/Canonicalize`

**Excluded:**

- `CS/Rule.idr`, where the coordinator adds `Cycle` ("cycle").
- `IDR/Ownership/Verify.cppm`: the owned-stage verifier is U03's.
- `IDR/Dialect/Verify`, which is U03's.
- Every test: U22 writes `T/idr/verify/cycle` and U23
  `T/reject/cycle-array-knot`.

## Read first

- `contracts.md` C10.1, C2.4, C1.6 and C13.
- `findings.md` F-prom-1, F-own-5 and F-poison-7.
- `findings/decision-acyclic-heap.md`.
- `IDR/Verify/Program.cppm`, all of it, to see how it runs before the
  ops' verifiers.
- `IDR/Canonicalize/Pass.cc`.
- The pinned `mlir/include/mlir/Transforms/Passes.h` (the
  `createCanonicalizerPass` overloads) and `GreedyPatternRewriteDriver.h`
  (`GreedyRewriteConfig`, its listener).

## Fixed decisions

- **The graph.**
  - Nodes: the module's `idr.data` declarations, and the element type of
    every array (`memref<?xE>`) a declaration's field or any value in the
    module names.
  - Edges: from a declaration to each declaration or array type that its
    constructors' field types name, looking through grades (`!idr.q`)
    and unboxed sums.
  - An array edge goes from the array to its element type's
    declarations.
  - A cycle through at least one array edge is rejected.
  - A memo sum (`idr.data ... memo`, C5.1) is an ordinary node; its
    cells are not mutable edges.
- **The message**, at the first `idr.array.new` whose element type is on
  the cycle, else at the module:
  `unsupported (cycle): an array of <T> can hold a reference to itself through <T> -> <U> -> ... -> <T>`.
  Types print as their declaration symbol names.
- **It runs inside `program(ModuleOp)`** like the other rules, so every
  pass is checked. Before `idr-defunctionalize`, closure captures are
  not types, which makes the check partial. Do not try to see through
  `!idr.fn`.
- **`idr-canonicalize`'s options.** It keeps its pass name, its options
  (`Passes.td` is unchanged for it) and its statistics. Only how it
  builds the canonicalizer changes.

## Inputs

- C10.1.
- The `Cycle` rule (C1.6), used by its phrase only.
- The memo attribute on `idr.data` (C1.1 item 5), read through the
  generated `getMemo()`.

## Outputs

- `IDR/Verify/Cycles.cppm`, partition `idr.verify:cycles`, exporting
  `LogicalResult cycles(ModuleOp)`, called from `program`.
- `idr-canonicalize` on upstream's constructor.

## Implement

- **`cycles`.** Build the graph with one pass over the `idr.data` ops
  and the types of the module's values. Run Tarjan's SCC over it, or
  use `IDR/Graph/Scc.cppm` if its interface fits a type graph; read it
  first. Report each strongly connected component that contains an
  array edge, once, with the path through it.
- **The sentinel.** Apply C2.4 to `IDR/Verify/Linearity.cppm`'s one
  site.
- **`idr-canonicalize`.** Build a `GreedyRewriteConfig` from the pass's
  options. Pass a `RewriterBase::Listener` that counts each pattern's
  rewrites into today's statistics, and create the pass with
  `createCanonicalizerPass(config, disabledPatterns, enabledPatterns)`.
  Run it as the nested pipeline the current code runs.

## Delete

- The copy of canonicalize's option handling in
  `IDR/Canonicalize/Pass.cc`.
- The `ub.poison` sentinel in `IDR/Verify/Linearity.cppm`.

## NOT TO DO

- Do not reject a cycle that has no array edge: immutable data cannot
  knot.
- Do not reject `IOArray (IOArray Int)`.
- Do not add a check of closures before defunctionalization.
- Do not add an IORef rule: there is no IORef op.
- Do not change the owned-stage verifier.
- Do not change `idr-canonicalize`'s options, name or counts.

## Acceptance

- The knot of `decision-acyclic-heap.md`, `data Node = MkNode (IOArray Node)`,
  is rejected after `idr-defunctionalize` with the message naming
  `Node`. `IOArray (IOArray Int)` passes. U22 and U23 write these from
  C12.
- A program with no arrays costs one graph build. The verifier does not
  walk ops more than once for this rule.
- `idr-canonicalize`'s counts in `--mlir-pass-statistics` and the round
  trace are unchanged on `T/idr/canonicalize`'s inputs. U22 keeps those
  tests.
- **Tempting partial:** checking only direct self-reference (`T` holds
  an array of `T`). Rejected: a knot through another type (`A` holds an
  array of `B`, and `B` holds an `A`) leaks the same way.

## Escalate if

- The verifier cannot see array element types of values that no
  declaration names. Report the case.
- `createCanonicalizerPass` at the pin does not accept a listener.
  Report the signature you found.

## Stop and return

You are done when `Cycles.cppm` is wired into `program`, the sentinel is
gone, and `idr-canonicalize` uses upstream's constructor. Return the
changed paths, `Verification: NotRun (swarm policy)`, and seams.
