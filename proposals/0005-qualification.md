<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0005: get back on track: the qualification (G1)

**Status:** decided 2026-10-12. What remains is G1 (§3), the run that
proves the tree on both targets. Each item is marked SELF-HOST (`make
self` needs it) or AFTER-SELF (it waits for `make self`, by the owner's
direction of 2026-10-15: self-hosting comes first). It keeps AGENTS.md's
two first-class targets (a change is done when it builds and passes on
both; a target that has not run an item is NotRun, never green) and its
no-oracle rule (the bench compares this compiler's output with clang's,
never Chez's: `bench/run.sh:17,53`). Claims are marked: *read* (the
path), *measured* (the record), *recalled*, *decision*.

## 1. Done

- The cutover this proposal designed (an in-tree MLIR dialect in
  upstream's layout, `idr.func` with inherent facts, analyses under the
  pass manager, function passes in parallel, no erased value emitted):
  1e1a3827, built since 4d5e7e8f (ad23fbb0); arm64 gate green at
  552d682a (`make check` 27/27, `make test-idr` 286/286, `make test`
  415/415; *measured* 2026-10-14, HANDOFF.md).
- G0, the baseline record: F0, `bench/profiles/2026-10-14-f0-stage0.md`.

Every wave since (the pipeline cutover, c7aa7b62 and 5d5f3312; the
representation wave, bfdcac70; 0002, d06ed15c; 0001, integrating now) is
integrated typecheck only. Nothing has run on a build machine since
c7aa7b62, and x86_64 Linux has run nothing.

## 2. Self-hosting

Moved to [0003-self-host.md](0003-self-host.md) on 2026-10-15.

## 3. G1

**When** (*decision*, D9, re-cut 2026-10-15). G1 runs once, on the tree
`make self` leaves; only its x86_64 Linux build comes first, since `make
self` holds only when it holds on both targets. Reason: no other item
decides whether the frontend compiles itself. The bench, the presets,
the compile-time baseline, the memory bound and the scan judge speed and
test scope, and the analyses check reads the first stage-0 record, which
`make self`'s stage 1 writes. Cost: the bench's bisect range, already
three unbenched waves past the 2026-10-13 record, grows by self-hosting's
changes; a bisect over more commits is the same procedure. The run
before the cutover, which was to give each target an old binary for the
pipeline cutover's §10 margins (its last text at 484d6403), was not
taken, so arm64 is read against the one record kept and Linux records
its own first baseline.

- **x86_64 Linux** (SELF-HOST). `make bootstrap` (every step of
  `tools/bootstrap.sh`: `llvm` alone builds neither GMP, nor Chez, nor
  Idris), `make build`, `make check`, `make test`, `make test-idr`,
  `make test-mlir-tools`: the first run of the runtime platform layer's
  Linux branches and the Linux check of the retirements PINS.md records.
  A failure that reproduces with upstream dialects and tools is a patch
  in `upstream/`; any other is ours, fixed in the tree. Waits on the
  owner's arm64 build and on §5's machine.
- **The bench** (AFTER-SELF). `bench/run.sh --record` on each target.
  On arm64 each program's ratio to its own C is read against
  `bench/runs/2026-10-13-9a1b7b1-darwin-arm64`; a ratio worse by more
  than 2%, best of five, is a regression, bisected and fixed (0008 D35,
  D36: the five-run spread reaches 97%, so it bounds nothing). Linux
  records a fresh baseline.
- **Compile times** (AFTER-SELF; *decision*, D19). `tests/compile-times.sh
  --record` on both targets, committed under `bench/profiles/`, is the
  first baseline: `bench/profiles/` holds F0 alone, and the 2026-10-13
  figure (167.9 s over 429 compilations) is *recalled*, in no file or
  commit. A pass that later grows against it is fixed or its cost
  stated. Reason: a threshold needs a baseline anyone can read.
- **The analyses, once each** (AFTER-SELF), from the first stage-0
  record: no `(A)` row of an analysis appears twice between two steps
  that both preserve it; the verifier's share per step and after
  `idr-rc`; the serial residue per step.
- **The other presets** (AFTER-SELF). `release` and `hardened` configure
  and build; `lint` builds under the pinned clang-tidy
  (`CMakePresets.json`).
- **Bounded memory** (AFTER-SELF). `tests/programs/eval/thunk-consumes-list`
  at 10^5 and 10^6: the larger run's max RSS under twice the smaller's,
  measured by `peak_memory` (`tools/host.sh:135`), the one host function
  `tools/self.sh` also uses. Not built: the fixture's `run` is `e2e_io .`
  and no test calls `peak_memory` (*read*).
- **The upstream-Idris scan** (AFTER-SELF; *decision*, D12, widened
  2026-10-15). `skip_reason` (`tests/upstream-idris/common.sh:69-114`)
  keeps by name a second copy of what the registry decides. Its arms go
  wherever the compiler decides the name: the raw-pointer arm
  (`:96-100`), since every name it scans is admitted (the pointers as the
  runtime's handles, `Registry/Libraries.idr:119-124` and
  `Registry/Recognized.idr:292-293`; `getEnv` and `getString` as
  primitives, `Registry/Primitives.idr:298, 376`), so a test that then
  fails is a failure; and the threads, finalizer and `unsafePerformIO`
  arms, whose names the registry refuses under an outside-the-language
  rule (`Registry/Recognized.idr:228-283, 295`; categories in
  `IdrBase.td:169, 187, 190`),
  so `rejection_skip` (`common.sh:124-129`) skips them by the refusal's
  rule category (`tests/lib/rules.sh`, generated from ODS), never its
  message. What the compiler never sees stays: other backends and the
  packages this compiler does not ship.

**Precise rejection messages** (AFTER-SELF; *decision*, D17; not G1).
Every refusal says what was found, where, why, and what form compiles
(the owner's request of 2026-10-10, HANDOFF.md). The four are fields of
the structured refusal (the `Rule` enum and its category in ODS,
`foreign/idr/include/idr/IR/IdrBase.td:145-177`), filled where each
refusal is decided, frontend and C++, and rendered in the one place that
writes the phrase. "Where" is the location the diagnostic already
carries, which 0001's `--report` prints, never a second copy. The reject
tests' expected files are rewritten in the same change, after G1's run.
Reason: a refusal's content changes those files, which G1 holds fixed.

## 4. Decisions in force

D9, D12, D17 and D19 are stated where they apply (§3). D13: this
proposal is deleted when G1 is green on both targets and D17 has landed.
Retired 2026-10-15: D1 (the order, now the owner's direction and
proposals/README.md's), D7 (the pipeline cutover's margins on stages
that are done), and D10, D11 and D16 (self-hosting's, now
0003-self-host.md's).

## 5. Open, for the owner

Where the x86_64 Linux leg runs. Default: a native x86_64 Linux machine
of the owner's, since the bench needs the target's hardware and no cross
run or emulation counts as green. Until one runs it, Linux is NotRun,
and `make self` with it.
