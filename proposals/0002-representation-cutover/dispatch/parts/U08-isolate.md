# U08 — idr-isolate: closure conversion on upstream's isolation

Mandatory findings: F-clo-7

## Permitted outcome

1. **The pass.** `idr-isolate` (a new `IDR/Isolate/` area) turns every
   `idr.lambda` and `idr.delay` into an `idr.closure` or `idr.suspend`
   of an outlined private function, using upstream's
   `makeRegionIsolatedFromAbove` (C4.3). Mandatory.
2. **The verifiers.** The two region ops' verifiers live in
   `IDR/Dialect/Ops/Regions.cc`. Mandatory.

## Owner / exclusive writes

- `IDR/Isolate`: `Isolate.cppm`, the pass glue `Pass.cc`, and
  `CMakeLists.txt` defining `idr_isolate`.
- `IDR/Dialect/Ops/Regions.cc`

**Excluded:**

- `INC/` (the coordinator writes the ODS and the pass definition).
- `foreign/idr/CMakeLists.txt` (the coordinator adds the `Isolate` area
  and links `idr_isolate`).
- `IDR/Dialect/CMakeLists.txt` (the coordinator adds `Ops/Regions.cc`).
- `IDR/Dialect/Registration` (the coordinator puts the pass first).

## Read first

- `contracts.md` C1.1 item 4, C4 (all) and C13.
- `findings.md` F-clo-7 and F-clo-6.
- `.toolchain/llvm-project/mlir/include/mlir/Transforms/RegionUtils.h:50-90`
  and its implementation in `mlir/lib/Transforms/Utils/RegionUtils.cpp`.
- `CS/Emit/Bodies.idr`'s `lifted`: the name, the attributes, the
  argument order.
- `IDR/Dialect/Ops/Lazy.cc`'s `SuspendOp::verify`, the world-capture
  rule.
- An existing small area's `CMakeLists.txt` and `Pass.cc`, for example
  `IDR/Stack/`.

## Fixed decisions

- **The algorithm is C4.3:**
  - post-order;
  - `cloneIntoRegion` true for `idr.constant` and `arith.constant`;
  - the new function `<enclosing>$lam<n>` or `<enclosing>$delay<n>`,
    with `n` counting per enclosing function in walk order from 0;
  - captures first, in the returned order, then the parameters;
  - each `idr.yield` becomes `func.return`;
  - the enclosing function's inheritable attributes and the lifted mark
    are copied;
  - the op is replaced with `idr.closure @name(captures)` or
    `idr.suspend @name(captures)`.
- **Moving the captures to the front.**
  `makeRegionIsolatedFromAbove` appends the captures to the block's
  arguments. To put them first, create the function's entry block with
  the final signature, `mergeBlocks` the region's block into it with
  the arguments in the new order, and erase the old block.
- **Which attributes are copied** is the list U07 reports from today's
  `lifted`. Read `Emit/Bodies.idr` yourself and use the same list; do
  not wait for the report. Both of you read the same source.
- **The `idr.lambda` verifier.** The block's argument types are the
  `!idr.fn` inputs, and every `idr.yield` in it yields the `!idr.fn`
  results.
- **The `idr.delay` verifier.** The block has no argument, and every
  `idr.yield` yields the lazy value's type. No value of world type
  defined above is used inside, which is the existing rule for a
  suspension's captures.

## Inputs

- The `IdrIsolate` pass definition and `createIdrIsolate` from
  `Passes.td`, which the coordinator writes.
- `LambdaOp` and `DelayOp` from ODS.

## Outputs

- `idr_isolate`, containing the pass.
- The two verifiers.

## Implement

- **The pass**, per the fixed decisions, in `Isolate.cppm`, with the
  glue in `Pass.cc`, as other areas split them.
- **The verifiers** in `Regions.cc`.

## Delete

Nothing outside your files. The Idris-side closure conversion this
replaces is U07's to delete.

## NOT TO DO

- Do not run the pass anywhere but first. The pipeline is the
  coordinator's.
- Do not keep regions alive past the pass (phase 2, C4.4).
- Do not specialize, inline or simplify while isolating.
- Do not capture a constant.
- Do not change `idr.closure`, `idr.suspend` or `idr.apply`.

## Acceptance

- An `idr.lambda` inside an `idr.match` region, using a block argument
  of that region and a value from the function's entry, becomes a
  closure of a function whose first two arguments are those two values,
  in walk order.
- A constant used inside is cloned, not captured.
- A lambda inside a lambda is outlined first, and its closure is a
  capture of the outer one's body only if the outer body uses it.
- Running the pass twice changes nothing the second time.
- U22 writes `T/idr/isolate/*` from C12.
- **Tempting partial:** outlining with `outlineSingleBlockRegion`, which
  makes a call in place of the body. Rejected: a lambda is a value, not
  a call; the op must become `idr.closure` of the outlined function.

## Escalate if

- `makeRegionIsolatedFromAbove` at the pin cannot clone a constant whose
  operands are themselves defined above. Report the constant op.

## Stop and return

You are done when the pass and the verifiers exist. Return the changed
paths, the hub text if C1.1 item 4 needs adjusting,
`Verification: NotRun (swarm policy)`, and seams.
