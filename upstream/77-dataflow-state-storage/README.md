<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][dataflow] One bit of liveness costs about 2.9 KB

On llvm main at 416f328b (the pin), `DataFlowSolver` keeps, behind every
lattice anchor with a state, a `DenseMap<TypeID,
std::unique_ptr<AnalysisState>>`, and inside every state with a
dependent a `SetVector<WorkItem>` with no inline size
(`mlir/include/mlir/Analysis/DataFlowFramework.h`, `analysisStates`,
`AnalysisState::dependents`, *read*). LLVM's `DenseMap` never allocates
fewer than 64 buckets once it holds anything, and such a `SetVector`
starts a 64-bucket `DenseSet` at its first insert, so "this value has a
state" is two minimum-size hash tables whatever the lattice holds: about
2.9 KB for a one-bit state with one dependent, *measured* on arm64 macOS
with the solver's exact container types over a million synthetic anchors
(audits/p0/wave1/5.1-mlir-analysis.md A4; glibc's allocator rounds
differently, by tens of percent, not by the factor). That, paid twice per
value, was most of the 627 GB that took exclusivity off the framework
(ffa91113). The solver also runs its program-point uniquer with locks,
though it runs on one thread (A5).

## Reproduce

The sizes are read from the container types; the heap per anchor was
measured with a harness of the solver's types (A4), not kept.

## Patch

`llvm.patch`, applying after 76 (05 touched the same header): an
anchor's map is a `SmallDenseMap<TypeID, ..., 2>`, a state's dependents a
`SetVector` with 4 inline elements, and the solver's uniquer is told it
runs on one thread (`disableMultithreading`): about 0.2 KB per state,
fifteenfold less (A4's P1), no API change. Not built; the qualification
measures it on Ranges, bytes per anchor on all four targets, the scale
fixtures and stage 1 (proposals/0000 C32, S3), and the record
goes here.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request to llvm/llvm-project, `[mlir][dataflow]`, with
  massif numbers on the in-tree sccp, int-range and liveness tests and a
  synthetic many-function module, as #135325's review asked of its kind.
- Upstream test: none of behaviour (NFC); the numbers are the PR's case.
- The patch goes when the pin's solver keeps small states inline.
