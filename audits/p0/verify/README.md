<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 cutover swarm

**Engagement (2026-10-21).** The implementation of
`proposals/0000-mlir-native.md`, written whole, in place, on `main`.
This packet was the verification swarm; its twenty reports
(`L01-*.md` to `L20-*.md`), `review.md` and `status.md` stay as the
evidence the proposal cites, and its lanes are now the cutover's.

- **The owner's choices:** one change, built only when whole (D56); a
  hard cutover with zero backwards compatibility (D6); four first-class
  targets; the owner's rulings D1 to D109 bind every lane, the
  coordinator's decisions C1 to C157 bind unless a lane shows a
  contradiction; the coordinator commits; no lane builds, typechecks or
  runs its part; INT builds and qualifies the whole on the owner's
  machines, since this one does not build LLVM.
- **The tree:** `main`, everything on it (the owner, 2026-10-21: "we
  should do everything on main"); the coordinator's P0 documents and this
  packet are committed on `main` before dispatch.

## The lanes: twenty-one writers and the integration tail

Every lane reads the representation-first skill, AGENTS.md and the whole
proposal first, then deeply its own sections, its verification report,
the audits and design documents of its area, and its code (each body's
**Read deeply**). Each writes only its paths (`ownership.json`); every
tracked file of the tree has exactly one writer or is one the cutover
never touches (`validate.sh`). Shared declarations are P0 §5's names and
shapes, so no lane waits on another; the few seams P0 left open are
fixed in the bodies (the generated names, `idr::tail::verify`,
`idr-simplify`, the inliner's `forget`, the CMake hubs).

| lane | area | recipe |
| --- | --- | --- |
| L01 | the effect tree and its one source | `L01-effects-ops.md` |
| L02 | rows, derivation, `idr.func` and `idr.call` | `L02-effects-rows.md` |
| L03 | the specification's core, generator and pipeline | `L03-one-source.md` |
| L04 | families | `L04-families.md` |
| L05 | the grade, lifetimes, linearity verification | `L05-lifetimes.md`, `design/lifetimes/lowering.md` |
| L06 | the toolchain, carried patches, pins | `L06-dispositions.md`, `upstream/README.md` |
| L07 | counting | `L07-counting.md` |
| L08 | exclusivity, the in-place promise, knots | `L08-exclusivity.md` |
| L09 | regions, matches, join points | `L09-control-flow.md` |
| L10 | proper tail calls, frame stacks, TRMC | `L10-tail-frames-stack.md` |
| L11 | the runtime, endings, memory, the driver | `L11-runtime.md` |
| L12 | arrays | `L12-arrays.md` |
| L13 | ops, the numeric template, rules as data | `L13-ops-canon.md` |
| L14 | the solver layer and the e-graph pass | `L14-analyses.md`, `design/egraph-full/mlir-form.md` |
| L15 | the compile-time C++ vocabulary | `L15-cxx.md` |
| L16 | the frontend and Emit | `L16-frontend.md` |
| L17 | the fork and its elaborator | `L17-fork.md` |
| L18 | defunctionalization, specialization, the optimizer | `L18-defunc-optimizer.md` |
| L19 | tests, harness, benchmarks | `L19-tests.md` |
| L20 | our Idris libraries | `L20-qtt-end-to-end.md` |
| L21 | the lowering to LLVM, the target | `L11`, `L02`, `L07`, `L13` (lowering parts) |
| INT | wire, generate, build, qualify | every handoff |

## The packet

- `parts/lanes/*.md`: each lane's body; `parts/common.md`: the common
  obligations (what to read, the contract, the rules of the code, the
  handoff); `parts/rules.md`: the six binding rules, verbatim.
- `dispatch/`: each lane's self-contained dispatch, assembled by
  `assemble.sh`.
- `ownership.json`: every writer's exclusive paths.
- `validate.sh`: every dispatch's sections and rules, no two writers
  meeting, every tracked file with exactly one writer. Recorded run: 22
  lanes, 324 writer paths, valid.

## Orchestrator prompt

1. Commit the P0 documents and this packet on `main`, run `assemble.sh`
   and `validate.sh`.
2. Dispatch every lane in `dispatch/` but INT, all at once, each told to
   read its dispatch in full and follow it. The session runs twenty
   agents at once: L21 starts the moment the first slot frees.
3. While they run: never stop a lane; message a quiet one. Review each
   handoff's diff against its lane's permitted outcome and NOT TO DO;
   send an overreach or a contradiction back to its writer. Commit each
   reviewed lane's paths. Write the absorbed proposals' amendments
   (D44, D69, D107) and P0's records as the coordinator.
4. When every lane has handed off, dispatch INT. Route each failure INT
   reports to the lane that owns the failing path, with the failure's
   text, and re-run INT, until every check passes on all four targets.
