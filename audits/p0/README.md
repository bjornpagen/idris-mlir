<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0, wave 2: the proposal applied to our codebase

Proposal P0 (`proposals/0000-mlir-native.md`) plans one total, hard
cutover of the compiler: upstream MLIR first, every `.td` definition and
effect redeclared, the `idr` dialect redesigned whole, no rederivation
chains, monomorphized C++26, our own solvers only where upstream cannot
(in one honest solver layer), and the Idris side refactored wherever the
representation calls for it. Wave 1 researched everything outside our
code and wrote the proposal's §5. Wave 2 reconciles that research with
every subsystem of our codebase, Idris and C++, one lane per subsystem,
each in its own document here. The coordinator then reconciles these
documents back into the proposal's plan (§7) with the owner.

The folder holds, beside the lanes' documents:
- `wave1/`: wave 1's research, moved out of the proposal unchanged on
  2026-10-21: `5.1-mlir-analysis.md` to `5.11-oom.md` (cited as "§5.N"),
  `00-brief.md` (the codebase brief and the walls, cited as "P0 §2" and
  "P0 §3"), `questions.md` (the 158 questions; every question ID
  resolves there).
- `synthesis/`: A to E, one per cluster; F, the questions as 84 decision
  points (DP-01 to DP-84); G, the coordinator's drafted decisions.
- `design/`: the centralized effect system, the measured causes of every
  slowdown, the compile-time C++ architecture.

Every lane reads, in full and in this order: the representation-first
skill (`.claude/skills/representation-first/SKILL.md`), `AGENTS.md`, the
proposal, `proposals/0003-facts-once.md`, and this file; then its own
subsystem, line by line, with its history.

## The lanes

| doc | lane | subsystem |
| --- | --- | --- |
| `01-ods-types.md` | ods-types | the type system: `IdrTypes.td`, `IdrAttrs.td`, grades, lifetimes, the program's table of data types, layouts, the verifier |
| `02-ods-effects.md` | ods-effects | traits, interfaces, effect resources, `Idr_Runtime`, the flow interface; every `getEffects` and `hasTrait` in the tree |
| `03-ods-ops.md` | ods-ops | every op definition, its C++ (`lib/IR/Ops*.cpp`), assembly, and the IR's core plumbing (regions, symbols, functions, bytecode) |
| `04-canon.md` | canon | canonicalization, folds, every pattern set and greedy-driver use |
| `05-analyses.md` | analyses | the analyses outside ownership and defunctionalization, the SCC utility, every dataflow-framework and analysis-manager use; the cross-cutting rederivation chains |
| `06-defunc.md` | defunc | the label solve, defunctionalization, deduplication, the effects pass |
| `07-ownership-analysis.md` | ownership-analysis | `Analysis/Ownership`: borrows, captures, exclusivity, reuses, uses, values |
| `08-counting.md` | counting | `Transforms/Ownership` (cells, grades, exclusive, knots, reuse, take), stack cells, demand |
| `09-optimize.md` | optimize | the optimizer, specialization, inlining |
| `10-tail.md` | tail | frames, accumulation, TRMC, tail loops, returned arguments, contification, the tail-call lowering |
| `11-arrays.md` | arrays | structure loops, bufferization, columns, narrowing, the array lowering, `libs/` |
| `12-conversion.md` | conversion | the lowering to func, memref and LLVM; the runtime-call layer; static data; counting's lowering |
| `13-driver-pipeline.md` | driver-pipeline | the pipeline, the driver, the target, the tools, the build, profiling, threading, verification's cost |
| `14-idris-dialect-side.md` | idris-dialect-side | `idris-mlir-tblgen` and the Idris side's view of the dialect: Dialect, Registry, MLIR, Encoding, Emit, Syntax |
| `15-frontend-translate.md` | frontend-translate | the frontend's translation of checked TT into `idr`: Translate, Walk, Resolve, Program; Term, Types, Ids, Loc |
| `16-frontend-checks.md` | frontend-checks | the frontend's refusals and analyses: Growth, Finite, Profile, Proof, Facts |
| `17-fork-boundary.md` | fork-boundary | the fork of Idris's compiler as the frontend consumes it: the TTC's facts, the two hosts |
| `18-runtime.md` | runtime | `runtime/`: allocation, counting, crashes, the stack, the platform layer |
| `19-tests-harness.md` | tests-harness | `tests/`, `harness/`, idr-expect and the contracts, the test APIs the cutover needs |
| `20-history.md` | history | the git history, the audits at 77eaa5b1, `PINS.md`, `upstream/`: every upstream mechanism dropped, patched or never adopted, and why |
| `21-perf-tracing.md` | perf-tracing | the tracing and performance work the owner's parallel agent pushes to `origin/main` (its stage-1 measurements and changes since e96bb991), reconciled with P0 and with lanes 01–20 |

## Each document's layout

1. **Reading notes.** What in the proposal bears on the subsystem, with
   section and finding IDs, written while reading it.
2. **What the subsystem is.** Its files and sizes, every fact it holds or
   derives, its data structures and state, who reads its results, its
   threading; *measured* where a count can be run.
3. **Reconciliation with the proposal.** For each wave-1 finding or design
   that touches the subsystem: holds, refuted, or holds in part, with the
   file and line that shows it. Every wave-2 question of §5 that falls
   here, answered by its ID.
4. **Issues.** A table, exhaustive over the subsystem: ID, `file:line`,
   category, what, proposed disposition. Categories:
   - *upstream*: an upstream mechanism replaces it (or would, patched);
   - *ods*: a declaration not yet made (a hand `verify`, `getEffects`,
     constraint, builder or list);
   - *rederivation*: a fact derived again that was known before;
   - *ladder*: an `isa<>` chain, a switch on a kind, a `get_if` chain, or
     callback plumbing where a trait, interface, template or concept
     belongs;
   - *list*: a hand-written list a generated table would hold;
   - *attribute*: a fact kept in a discardable attribute;
   - *state*: per-value or per-point state a representation or a dense
     numbering would remove;
   - *budget*: a cap, round count or limit, and whether it can fail;
   - *per-target*: a target case outside the target's entry;
   - *cpp*: C++ to modernize (templates, concepts, `std::visit`,
     `function_ref`, types);
   - *idris*: an Idris-side representation to change (type-driven:
     indices, `Dec`, views, erased proofs);
   - *dead*: a definition nothing uses.
5. **Target design.** What the subsystem becomes, applying the proposal:
   for each change, the representation, what it deletes, and the one
   line the skill asks for (the state made unrepresentable, the check
   moved to a boundary, or the branch deleted; or why the case is
   essential). Its order inside the subsystem and its dependencies on
   other lanes.
6. **Evidence for the owner's questions.** For each §8 question the
   subsystem bears on, by ID: what our code says. No answers: the owner
   decides. New questions for the owner, if any.
7. **Deletion list.** What goes, by file and symbol.
8. **Risks, unknowns, measurements needed.**
9. **Sources read.** Every file, commit and proposal section.

## Rules

- A lane writes only its own document. Nothing else changes: no code, no
  proposal, no other document, no build, no git command that writes.
- Claims are marked *read* (`path:line`, a commit, a proposal section),
  *measured* (a count, with its command), *recalled* or *conjecture*.
- The owner's questions (proposal §8) are the owner's: a lane gives
  evidence, never a decision.
- The Idris side compiles under both hosts (AGENTS.md); its refactors stay
  in that subset.
