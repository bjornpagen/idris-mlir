# U12 — Static data marked and flat: static memo cells by kind, runs lowered by a loop

Mandatory findings: F-lazy-4 F-poison-4 F-const-3

## Permitted outcome

1. **Static memo cells.** A constant of a memo-sum box lowers to a
   private, non-constant `llvm.mlir.global` whose initializer is the
   cell's image:
   - count 0;
   - the label's info word, with kind `IDRIS_RT_KIND_THUNK`;
   - the persistent captures.

   Every other static global is `constant`. Constant static data that
   points at a static memo cell (a constant stream's tail) holds its
   address (C5.5). Mandatory.
2. **`@__idr_release_cafs`.**
   `StaticData::emitReleaseCafs(OpBuilder &)` builds
   `func.func private @__idr_release_cafs()`, which calls
   `idris_rt_caf_release` on each static memo cell's address. It is
   built always, with an empty body when there is none. Mandatory.
3. **Runs by a loop.** A `#idr.con` run (C7) lowers to its static cells
   with a loop over the run, without recursion on its length.
   Mandatory.
4. **The sentinels.** The two C2.4 sites in `StaticData.cppm` use no
   sentinel. Mandatory.

## Owner / exclusive writes

- `IDR/Lower/StaticData.cppm`

**Excluded:**

- Every other `IDR/Lower` file. `Runtime` (U11) calls you through the
  same `constant` and `message` signatures, and calls `emitReleaseCafs`
  from `Runtime::finish()`.
- `IDR/Dialect/Attrs` (U19 defines runs).
- `RT/` (U15 defines `idris_rt_caf_release`).
- `IDR/Lower/Entry.cppm` (U13 calls `@__idr_release_cafs`).

## Read first

- `contracts.md` C5.5, C7.1, C7.2, C1.5 and C13.
- `findings.md` F-lazy-4, F-const-1 and F-const-3.
- `IDR/Lower/StaticData.cppm`, all of it (`frozen`, `staticCell`,
  `global`, `constant`).

## Fixed decisions

- **The global.** It is
  `LLVM::GlobalOp::create(..., isConstant = false, Linkage::Private, name, ...)`,
  with the name prefix `__idr_caf_`. It is not thread-local. C5.5 says
  why.
- **The release function.** `emitReleaseCafs` creates
  `@__idr_release_cafs` once per module. It holds one
  `llvm.call @idris_rt_caf_release(%addr)` per static memo cell, where
  `%addr` is `llvm.mlir.addressof` of its global.
- **Runs.** `ConAttr::isRun()` and `getRunLength()` say whether a
  constant is a run. Lower its cells from the tail back to the head in
  one loop, each pointing at the previous global. A plain con lowers as
  today.
- **`frozen`.** Every static cell is `constant`, unless it is a memo-sum
  box.

## Inputs

- Memo sums, and U10's `Layouts::isMemo(Type)`.
- `ConAttr`'s run API (C7.2), owned by U19.
- `idris_rt_caf_release` (C1.5).

## Outputs

- Static memo cells.
- `@__idr_release_cafs`, built by `StaticData::emitReleaseCafs(OpBuilder &)`.

## Implement

- Per the fixed decisions.
- Apply C2.4 to the two sites.

## Delete

- The `frozen = !isa<LazyType>(...)` rule and its comment.
- Every static path for `LazyType` and closure constants
  (`__idr_closure_`). After defunctionalization a constant thunk is a
  memo-sum box, and a constant closure a closure-sum constructor.
- The two `ub.poison` sentinels.

## NOT TO DO

- Do not make any other static data mutable.
- Do not keep a runtime list.
- Do not make the memo cell thread-local (C5.5).
- Do not recurse on a constant's list length.
- Do not change string, bignum or message globals.

## Acceptance

- A lazy constant lowers to one non-constant global with the thunk
  kind, listed in `@__idr_release_cafs`. A constant stream whose tail is
  that thunk is a `constant` global holding its address. U22 writes
  `T/idr/lower/static-thunk`.
- A 10^5-cell run lowers without a stack deeper than a constant number
  of frames. The coordinator runs `T/programs/eval/deep-list-constant`
  on an 8 MiB stack.
- Every non-constant global `StaticData.cppm` creates is a memo cell.
- **Tempting partial:** keeping `frozen` and adding the kind beside it.
  Rejected: two marks for one fact; the kind is the mark.

## Escalate if

- A static memo cell is reachable from a constant that must be
  thread-local for another reason. Report the constant.

## Stop and return

You are done when the four outcomes are in `StaticData.cppm`. Return
the changed paths, `Verification: NotRun (swarm policy)`, and seams.
