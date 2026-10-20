<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The toolchain bump

**Status (2026-10-19):** queued after `make self` (**AFTER-SELF**). The
survey below was taken on 2026-10-15, read-only, against that day's heads.
It must be redone when the bump runs, because our side has moved since:

- **The pins have not moved** (`toolchain.lock.json`, the gitlinks):
  - llvm-project main 7208ba24;
  - Idris 2 1c630e67;
  - CMake v4.2.8;
  - Chez Scheme v10.4.1.
- **The toolchain was rebuilt on 2026-10-19 at the same pins.** It carries
  the LLVM patches through 61. Patches 62 and 63 (4dde6b7f) are written and
  wait for the next rebuild, which is the coordinator's and is not this
  bump (`proposals/0001-self-host.md`, step 1).
- **The patch set has more than doubled.** The survey checked nine carried
  LLVM patches. Eighteen are carried now (`tools/patches.sh` lists them in
  order):

  | Patches | When they came |
  |---|---|
  | 03, 04, 05, 06, 07, 09, 19, 23 | before the survey |
  | 24 | before the survey; reworked on 2026-10-19 (two fixes) |
  | 28, 29, 30, 56, 57, 60, 61, 62, 63 | after the survey |

  30 is an AArch64 code generation patch, so `check-llvm` judges it as
  well as `check-mlir`.

  The submissions not carried are now 02, 08, 16, 17, 22, 25, 27 and 58.

- **The fork carries new fixes against Idris's pin.** The ones added since
  the survey are 50 to 55, 59 and `fork-ttc-term-locations`. Each fork fix
  has a `pull-request.diff` that a re-sync reads.

Self-hosting needs nothing from this bump. Stage 2 equal to stage 3 on the
new pins is the bump's strongest check, so the bump waits for `make self`.
If self-hosting meets a bug that a newer upstream fixes, AGENTS.md
backports the fix as a patch, and the bump still waits.

The pin policy is AGENTS.md's. This file holds only what moves, and why.

| Tool | Pinned | Target | Verdict |
|---|---|---|---|
| llvm-project | main 7208ba24 | main when the bump runs | bump: survey again, then rebase 06, refresh 07, retire 01's pin entry |
| Idris 2 | 1c630e67 | main when the bump runs (89ba32eb on 2026-10-15) | bump: base only, as of 2026-10-15 |
| CMake | v4.2.8 | the newest release when the bump runs (v4.4.4 on 2026-10-15) | bump |
| Chez Scheme | v10.4.1 | 10.5.0 once tagged (none on 2026-10-15) | stay until tagged |
| Ninja, GMP, simdutf, fast_float, snmalloc | v1.13.2, v6.3.0, v9.3.0, v8.3.2, 0.7.6 | the newest release when the bump runs (each was its newest on 2026-10-15) | check |
| ryu | 4c0618b (v2.0-108) | stays (D3) | stay |

## LLVM

When the bump runs, on main as it is then:
- Each `upstream/*/llvm.patch` goes through `git apply --check`, first
  alone, then in name order, as `tools/bootstrap.sh` applies them.
  `tests/upstream-patches` checks them on the new pin.
- Each submission's `pull-request.diff` is checked the same way.
- The LLVM and MLIR headers our C++ includes are diffed against the pin's.
  This covers every consumer the 2026-10-15 survey did not read:
  - googletest and googlemock (`foreign/idr/unittests`);
  - compiler-rt's `FuzzedDataProvider.h` (`harness/prop`);
  - `PassInstrumentation` (`lib/Transforms/Contracts`);
  - `DialectReductionPatternInterface`
    (`tools/idris-mlir-reduce.cpp`);
  - whatever the patches since 24 touch.
- `check-mlir`, and `check-llvm` for 30, runs on a build of the new pin
  with every carried patch. These suites are what showed patch 24's two
  bugs (upstream/README.md).
- Each patch whose fix main now has retires as AGENTS.md says. Its report
  is kept as a submission or deleted, and its PINS.md entry and its
  `tests/upstream-*` go with it.

What the survey found at 7a83be39 and the status table still holds
(`upstream/README.md`):
- **06:** its function-argument hunk (`cleanUpDeadVals`) conflicts with
  main's #208881 (0edf6243), which does what that hunk does. Drop the hunk,
  leaving one copy of the rule (main's). Then rewrite 06's pull request
  text and its comment on #208881. PINS `remove-dead-values-unreachable`
  stays, with its condition changed to "the pin has the rebased PR".
- **01:** PINS `remove-dead-values-address-taken` and
  `tests/upstream-remove-dead-values-address-taken` retire, since their
  condition is "the pin has #208881". 01's report stays, as the test-only
  pull request.
- **07:** it applied with an offset (d8b7bd11 changed `Inliner.cpp`).
  Refresh it.

Behaviour the suites judge, from main's log at 7a83be39, to read again
over the new range:
- scf-to-cf's non-wrapping increment (9e00863f);
- remove-dead-values' poison for dead arguments (0edf6243);
- bufferization (5e248845, d2146051);
- arith-to-llvm (a5d2f05b, dd0c1922);
- scf peeling of the first iteration (fa1e20e8, 15106899), where our
  schedule peels the last.

## Idris 2

On 2026-10-15, main (89ba32eb) was two commits past the gitlink, and
neither touched `src/`:
- b6cbc25d made `Data.Vect.fromList` structural;
- 89ba32eb gave five buffer primitives a `RefC:` spec.

When the bump runs:
- Move the gitlink. Move the fork's recorded base: `idrisVersion` in
  `compiler/idris/src/IdrisPaths.idr`, and `compiler/idris/README.md`.
- Every fork fix's `pull-request.diff` must apply to the new base. On
  2026-10-15 every diff then in the tree applied to 89ba32eb (*measured*).
  The diffs added or changed since have not been checked against any later
  main (`git log -- upstream` lists them).
- Base arrives with the gitlink (`make prefix`). The registry matches a
  `%foreign` definition by any spec it knows (`declares`,
  `compiler/src/IdrisMLIR/Registry.idr`), so a new spec resolves as before.
  A base change to a name the registry recognizes is a registry change, in
  the same commit.
- The stock Idris the bootstrap builds carries no `idris.patch`.

## CMake and Chez

- **CMake.** The lock's `cmake` entry moves: the revision, the tag, the
  version, and `accept`, which the gate in `CMakeLists.txt` reads.
  - On 2026-10-15, for 4.4.4, nothing else had to change.
    `cmake_minimum_required(VERSION 4.0)` keeps the new policies of 4.3
    and 4.4 (CMP0205 to CMP0219) at their old behaviour.
  - Presets schema 8 stays valid.
  - The bootstrap's `./bootstrap` and its version check work unchanged.
  - Read the release notes again for whatever release is newest then.
- **Chez.** On 2026-10-15, main was 10.5.0-pre-release.1, 24 commits past
  v10.4.1, with W^X support (00772bf, 5ee2152) that arm64 macOS benefits
  from. No `chez.patch` is carried. Chez moves when 10.5.0 is tagged.

## Order

1. `make self` holds on the four targets, on the current pins.
2. **Idris 2, alone** (it rebuilds no LLVM). Move the gitlink and the
   fork's recorded base. Then, on each target: `tools/bootstrap.sh
   idris`, `make fork`, `make build`, the suites, `make self`.
3. **CMake and LLVM together**, so that LLVM is rebuilt once.
   - Run the LLVM checks above.
   - Make one commit: the lock's `cmake` and `llvm` entries, the reworked
     patches, the retirements, and 06's new condition.
   - On each target, run `tools/bootstrap.sh cmake llvm`, every check
     AGENTS.md names, and `make self`. Then regenerate the typecheck build
     (`make typecheck`).
4. **The PINS.md tombstone sweep**, against the new pins.

Acceptance: `make self` holds on the four targets at the new pins, with
every check AGENTS.md names.

## Decisions

- **D1.** Idris goes first and alone, then CMake with LLVM. Reason: LLVM's
  build is the cost, so it is paid once.
- **D2.** Chez takes releases only (the pin policy).
- **D3.** ryu stays at 4c0618b, the head of its master branch when it was
  pinned, 108 commits past v2.0 (2019), its last release.
  - Reason: the pin policy's "latest release" exists to keep each
    dependency at its newest maintained state. ryu's maintained state is
    its master branch, since it has made no release in seven years.
    Going back to v2.0 would drop 108 commits of fixes for the letter of
    the rule.
  - The bump moves it to master's head at the time, if master has moved.
  - The deviation is recorded as a PINS.md entry, as every deliberate
    deviation is.

## The MLIR form owed

From the representation wave's audit of the proposals' MLIR forms (its
last text at 77eaa5b1), checked against the code there; none of it is
built unless it says so.

- Patch 06's choice is made: drop the hunk, as its own plan says
  (`upstream/06-remove-dead-values-unreachable/README.md`), so main's
  #208881 is the one copy.
- Each bump checks our fills of upstream's gaps against main and deletes,
  in the same commit, what main now covers: `transform.idr.vectorize_lanes`
  (`ScheduleOps.td`, `Schedules.cpp`), `idr.tie_shape`, `LowerGetGlobal`
  (`Conversion/Arrays.cpp`), patch 24 and U2; and the ready set beside
  `mlir::Inliner` (0008).
