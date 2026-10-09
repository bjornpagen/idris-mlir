# 0003: pin LLVM to a trunk commit

**Status:** decided (2026-10-09). The pin is llvm main 7208ba24. It was
first built on arm64 macOS, with `upstream/` 02-07, 09 and 15, where
`make build`, `make check`, `make test`, `make test-idr` and
`make test-mlir-tools` passed, once five failures that were bugs of ours
from the lazy-streams merge (2726706c), which 23.1.2 shows too, were fixed
in their own commit. That build ran the bootstrap's Darwin recipe, and the
x86_64 Linux recipe was never run at the pin: the cutover held for one
target. The user ruled per-target cases out, so the toolchain is now one
recipe for both targets (`tools/bootstrap.sh`: stage 1, the target's C
library, the runtimes and stage 2, into `.toolchain/llvm`, with only what
the target's operating system forces decided in one place), one preset set
reading the toolchain file stage 2 writes, the backends of both targets in
every LLVM, and every check on every target (11's included). Open: step 5
on both targets, with the patches the tree carries now (16 and 19 besides
those above, and Idris's 18); until then no toolchain is current on
either. `idr-simplify` runs `composite-fixed-point-pass` with
`on-convergence-failure=silent`, not `error` (step 4; PINS.md
`simplify-structural-fixpoint`).

## Decision

The LLVM pin moves from `llvmorg-23.1.2` to llvm main at
`7208ba24ca2894729cd394475a00d2a7b605e642` (2026-10-08, LLVM 24 in
development). It is a pinned commit, not a followed branch: a bump is
one deliberate change with its own rebuild and suites. It is a hard
cutover: every workaround, pin and patch that exists only because
23.1.2 lacked something on main goes in the same change, and the trunk
mechanisms that replace our own are adopted.

## Why

- **One diff per bug.** Every fix in `upstream/` is sent to main. On a
  release pin, three of them need a second diff for the pin, and the two
  drift. On a trunk pin, `llvm.patch` is the pull request, and it goes
  the moment the pin moves past its merge.
- **Tested base.** Main at 7208ba24 with all seven code diffs of
  `upstream/01-08` passes `check-mlir` (4102 passed, 0 failed, Release
  with assertions; `upstream/README.md`). Nothing on 23.1.2 has that.
- **Pins that exist only for 23.1.2 go:** `13-uplift-final-counter`
  (6e714c8d9 is on main), `14-while-move-if-down-duplicates` (a65eb8723
  is on main), the backported half of `15-ld64-lld-unknown-tapi-target`
  (532fa5afb) and of `09-int-range-narrowing-exactness` (44a4dbf32).
- **Trunk has what our workarounds wait for.**
  `composite-fixed-point-pass` has `on-convergence-failure` on main
  (#218394), the condition PINS.md `simplify-structural-fixpoint` names
  for replacing `idr-simplify`'s own fixpoint loop with the upstream
  pass. The macOS port wants trunk's ld64.lld TAPI fixes.
- **A release buys nothing here.** 24.1 is months away. A release suits
  a downstream that cannot rebuild LLVM; this repository builds its own.

## Costs

- MLIR's C++ API changed between 23.1.2 and 7208ba24, so foreign/idr
  needs fixes. Bounded, and better now than in the middle of 0002's
  lanes.
- Trunk clang can carry a codegen regression; the full suites after the
  rebuild are the check. A regression found is reported upstream with a
  reduced test and carried as a patch, as `upstream/README.md` says.
- `tools/bootstrap.sh` clones the pin by tag (`git clone --branch
  <tag>`); a trunk commit has no tag, so the clone, the version flags
  and the lock entry learn an untagged revision.

## Rust (proposal 0001)

rustc ships its own LLVM, a fork of the current release: nightlies have
used LLVM 23 since July 2026 (rust-lang/rust#158734; Bun's
nightly-2026-09-15 bundles 23.1.1), and rustc builds against an
external LLVM 22 or 23 (rust-lang/rust#163572). It does not build
against an unreleased LLVM 24, so 0001's R0 plan, rustc built against
our stage-2 LLVM ("one LLVM"), does not hold on a trunk pin until Rust
moves to LLVM 24 (expected after LLVM 24 branches, early 2027).

It does not need to. 0001 already states the fallback: bitcode LTO
works while rustc's LLVM major is not newer than ours, because newer
LLVM reads older bitcode. So R0 pins an official nightly with its
bundled LLVM, joins its bitcode with ours, and `verify-pins` enforces
rustc's LLVM major <= ours. That drops rustc's hour-long source build
from the bootstrap. When a nightly on our major exists, building rustc
against our LLVM becomes possible again and can be revisited; it is not
required for correctness. 0001's §14 R0 and §15 are amended to say so.
Nothing of Rust is built in this cutover.

## The cutover, in order

1. **Bootstrap learns an untagged pin.** `toolchain.lock.json` llvm:
   `revision` 7208ba24, `describe` (`git describe` against the
   `llvmorg-24-init` tag), `version` as its `LLVMVersion.cmake` says
   (24.0.0git), `accept` "24". `clone_pinned` fetches the revision
   (`git init`, `git fetch --depth 1 <repo> <revision>`) when there is no
   tag; `llvm_revision_flags` and anything that prints the version read
   the lock. `tests/Lock.idr` already accepts `describe` for an untagged
   entry.
2. **Patches become the pull requests.** For each `upstream/NN-*` with a
   `pull-request.diff` and an `llvm.patch` (04, 06, 07), the trunk diff
   becomes `llvm.patch` and `pull-request.diff` goes; 02, 03 and 05
   already apply to main unchanged. 08 stays `pull-request.diff` only
   (the compiler does not carry it). `upstream/README.md` says
   `llvm.patch` is the pull request.
3. **Retire what main has.**
   - 13 and 14: delete the directories, `tests/upstream/<bug>/` and the
     PINS.md entries; check whether idris-mlir-opt's copy of the
     uplift test pass is still needed (PINS.md `uplift-final-counter`).
   - 15: drop the 532fa5afb half; the local unknown-triple skip stays.
   - 09: drop the 44a4dbf32 half; rerun its three remainder cases on
     the new pin; keep them as a bug of ours only if they still fail.
   - 10, 11, 12: run each `tests/upstream/<bug>/` against the new pin;
     a fixed one retires the same way.
   - PINS.md entries whose retire condition names a toolchain bump
     (`llvm-cxx17-headers`, `llvm-force-enable-stats`, `clang-no-reflection`)
     are checked and retired or kept with the reason.
4. **Adopt trunk mechanisms.** `idr-simplify`'s fixpoint loop becomes
   `composite-fixed-point-pass` with `on-convergence-failure` set to
   fail, if its statistics and remarks can stay ours (PINS.md
   `simplify-structural-fixpoint`); otherwise the entry says what is
   still missing. Read the MLIR changes between 23.1.2 and 7208ba24 for
   any other mechanism a PINS entry or a workaround in foreign/idr is
   waiting for, and list them in `findings/` with what was adopted.
5. **Build and fix, on each target.** `tools/bootstrap.sh llvm` (stage 1,
   the target's C library, the runtimes and stage 2; hours), the same
   recipe on both. Fix foreign/idr against main's API. `make build`,
   `make check`, `make test`, `make test-idr`, `make test-mlir-tools`,
   all green on each target. The runtime is rebuilt with fast_float 8.3.1
   and snmalloc 0.7.6 (already pinned).
6. **Record.** PINS.md (the pin, every retired entry gone, the bump
   policy: bump when a patch of ours lands, or about monthly, each bump
   one commit with the suites), `sources/` snapshots pointed at the new
   commit, `upstream/README.md`'s toolchain section, and 0001's R0.

## Not in this change

Rust itself; 0002's work (it runs after, on the new base); new
features beyond the trunk mechanisms above.
