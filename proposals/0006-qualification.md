<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0006: the qualification (G1)

**Status (2026-10-19):** open; none of G1 has run. G1 is the one run that
qualifies the tree's speed, scope and memory on every target. It starts on
the tree `make self` leaves (**AFTER-SELF**). On each Linux target it
starts once 0002's build and suites pass there.

The pieces G1 needs exist:
- the build, the suites and determinism run on arm64 macOS on every
  change (the `tests/determinism-*` tests, `harness/lib/determinism.sh`);
  G1 adds one record of the self-hosted compiler compiling itself at each
  thread count `harness/lib/determinism.sh` names, all byte-identical
  (`make self` itself compares at the default count only);
- the bench, `bench/run.sh`;
- the compile-time recorder, `tools/compile-times.sh`.

The Linux targets have built nothing yet. Their builds, suites and the
machines they run on are 0002's.

This proposal keeps AGENTS.md's four first-class targets: a target that
has not run an item is NotRun, never green. It also keeps the no-oracle
rule: the bench compares this compiler's output with clang's, never with
Chez's (`bench/README.md`). Claims are marked *read* (the path),
*measured* (the record), *recalled* or *decision*.

## 1. G1

Each item says what is owed, what proves it done, and what it waits on.
All of them wait on `make self` (0001). On Linux they also wait on 0002's
build and suites.

- **The bench.** Run `bench/run.sh --record bench/records/<…>` on each
  target. The record is committed.
  - On arm64 macOS, each program's ratio to its own C is read against
    `bench/records/2026-10-13-9a1b7b1-darwin-arm64`. The comparison only
    covers programs whose `Main.idr`, `main.c` and input are the
    record's. A ratio worse by more than 2%, best of five, is a
    regression; it is bisected (`tools/bisect.sh`) and fixed (D1).
  - A program the record lacks, or one whose source or input changed
    since, records its first baseline. Since the record, d346040c added
    chameneos-redux, meteor-contest, regex-dna and thread-ring, and
    reworked several programs, the mandelbrot pair among them.
  - Each Linux target records its first baseline.
- **Compile times.** Run `tools/compile-times.sh --record` on each target,
  committed under `bench/records/`. It is the first compile-time baseline
  (D2).
- **The analyses, once each.** Read stage 1's pipeline record (0001's S3).
  - No `(A)` row of an analysis appears twice between two steps that both
    preserve it.
  - Record the verifier's share per step and after `idr-rc`.
  - Record the serial residue per step.
- **The other presets.** `release` configures and builds. `lint` builds
  under the pinned clang-tidy (`CMakePresets.json`, whose presets are
  `base`, `dev`, `release`, `lint` and `typecheck`).
- **Bounded memory.** `tests/leet-relink-in-place` at 10^5 and 10^6
  elements.
  - Acceptance: the larger run's max RSS stays under twice the smaller's,
    measured by `peak_memory` (`tools/host.sh`), the one host function
    `tools/self.sh` uses too.
  - Not built yet: the fixture checks its program's reuse
    (`mlir.expect`), and no test calls `peak_memory` (*read*).
- **The upstream-Idris scan** (D3). `skip_reason`
  (`tools/upstream-idris/common.sh:76`) keeps, by name, a second copy of
  what the registry decides. Its arms go wherever the compiler decides the
  name:
  - **The raw-pointer arm.** Every name it scans is admitted: the pointers
    as the runtime's handles, `getEnv` and `getString` as primitives
    (`Registry/Primitives.idr`). A test that then fails is a failure.
  - **The threads, finalizer and `unsafePerformIO` arms.** The registry
    refuses those names under an outside-the-language rule
    (`Registry/Recognized.idr`; the categories are in `IdrBase.td`). So
    `rejection_skip` skips them by the refusal's rule category, never by
    its message. It already exists (`common.sh:124`).

  What the compiler never sees stays as it is: other backends, and the
  packages this compiler does not ship.

  Acceptance: `skip_reason` names no identifier the registry decides.

**Precise rejection messages** (not G1; D4). Every refusal says four
things: what was found, where, why, and what form compiles.

Today a refusal (`#idr.refusal`, `foreign/idr/include/idr/IR/IdrAttrs.td`)
holds three of them, and `idr::refuse` is its one printer:
- what was found: the message;
- where: the location;
- why: the rule, whose phrase and category are in `IdrBase.td`.

What is owed is the fourth: what form compiles. It becomes a field of the
refusal, filled where each refusal is decided (frontend and C++) and
printed by `idr::refuse`. The reject tests' expected files are rewritten
in the same change. That change comes after G1's run, which holds those
files fixed.

Acceptance: no refusal is constructed without that field.

## 2. Decisions

- **D1.** A bench regression is a ratio worse by more than 2%, best of
  five, against the record (0009 D35, D36). Reason: the five-run spread
  reaches 97%, so the spread itself bounds nothing.
- **D2.** The first `tools/compile-times.sh --record` on each target is
  that target's baseline. A pass that later grows against it is fixed, or
  its cost is stated. Reason: a threshold needs a baseline anyone can read.
  The 2026-10-13 figure (167.9 s over 429 compilations) is *recalled* and
  is in no file or commit.
- **D3.** The scan's skips are decided by the compiler: by an admitted
  name's result, or by a refusal's rule category. Reason: one fact, one
  place.
- **D4.** "What form compiles" is a field of the structured refusal. It is
  never a second text kept beside the message, and "where" is the location
  the diagnostic already carries. Reason: the four facts are one record.
- **D5.** This proposal is deleted when G1 is green on the four targets and
  D4 has landed.

## The MLIR form owed

From the representation wave's audit of the proposals' MLIR forms (its
last text at 77eaa5b1), checked against the code there; none of it is
built unless it says so.

- D4's structured refusal, partly built: `#idr.refusal<rule, loc,
  message>` is the frontend's transport and the diagnostic's metadata holds
  the bare `RuleAttr` (`lib/IR/Attrs.cpp`). Owed: "found" a typed field,
  not text; the metadata holding the refusal attribute; "what form
  compiles" an `attachNote`; "why" the rule's phrase generated from
  `Idr_Rule`, rendered once, by the driver's handler.
- "The analyses, once each" reads `-mlir-timing`'s analysis rows, so it
  covers only managed analyses: Exclusivity becomes one first ("Each fact
  once", ownership: idr-rc-commit reading the solve with
  `getCachedParentAnalysis`; idr-rc's steps are `addRc` in
  `Pipeline.cpp`, the commit `Ownership/Exclusive.cpp`).
