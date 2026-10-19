<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The toolchain bump

**Status:** prepared 2026-10-15, read-only, against that day's heads.
Nothing was built or filed, and nothing was sent to Idris. It is queued
after `make self` (**AFTER-SELF**), for two reasons. Self-hosting needs
nothing from it. And stage 2 equal to stage 3 on the new pins is the
bump's strongest check. If self-hosting meets a bug that a newer
upstream fixes, AGENTS.md backports that fix as a patch, so the bump
still waits. The pin policy is AGENTS.md's, and the pins are
`toolchain.lock.json` and the gitlinks. This file holds only what moves,
and why.

| Tool | Pinned | Target | Verdict |
|---|---|---|---|
| llvm-project | main 7208ba24 | main when the bump runs; surveyed at 7a83be39 (main was 2138b6cd later the same day, *measured*) | bump: rebase 06, refresh 07, check 24 again |
| Idris 2 | 1c630e67 | main 89ba32eb (still main, *measured* 2026-10-15) | bump: base only |
| CMake | v4.2.8 | v4.4.4, the newest release (4.5.0-rc1 is a candidate) | bump: the gate's series moves |
| Chez Scheme | v10.4.1 | v10.4.1 (no 10.5.0 tag yet) | stay until 10.5.0 is tagged |
| Ninja, GMP, simdutf, fast_float, snmalloc | v1.13.2, v6.3.0, v9.3.0, v8.3.2, 0.7.6 | the same: each is its newest release (*measured*) | stay |
| ryu | v2.0-108 | no release since v2.0 (2019) | the owner's question (Decisions) |

## LLVM

Surveyed at 7a83be39, 1253 commits past the pin and still LLVM 24.0.0,
so the lock's `accept: "24"` holds. The survey ran in a blobless scratch
clone (*measured*). When the bump runs, the same checks run again against
main as it is then:
- each `upstream/*/llvm.patch`, with `git apply --check`, alone and then
  in name order, as `tools/bootstrap.sh` applies them;
- each submission's `pull-request.diff`;
- the headers our C++ includes, diffed.

What the survey found at 7a83be39:
- **Carried patches.** 03, 04, 05, 09, 19 and 23 apply cleanly.
  - 07 applies with an offset, because d8b7bd11 changed `Inliner.cpp`.
    Refresh it.
  - 06 conflicts in its function-argument hunk (`cleanUpDeadVals`), and
    main's #208881 (0edf6243) does what that hunk does. Either drop the
    hunk, which leaves one copy of the rule (main's), or route main's
    loop through the patch's `replaceUsesWithPoison`. Then redo 06's PR
    text and its comment on #208881.
  - 24 was checked before 26 was folded into it, and has changed since.
    Check it again.
- **Submissions.** 02, 08, 16, 17, 22 and 25 apply cleanly; 27 applies
  with an offset. None of their bugs is fixed on main.
- **What retires.** PINS `remove-dead-values-address-taken` (01) and
  `tests/upstream/remove-dead-values-address-taken` retire, since their
  condition is "the pin has #208881". 01's report stays, as the
  test-only PR. PINS `remove-dead-values-unreachable` (06) stays, with
  its condition changed to "the pin has the rebased PR".
- **The API.** None of the 277 LLVM and MLIR headers our C++ included
  was removed. Nineteen changed, and none needs a code change. Among
  them:
  - `TimeTraceScope` became `[[nodiscard]]`;
  - TableGen's record storage changed (`getAllDerivedDefinitions` still
    sorts with `LessRecord`, so generated files keep their order);
  - `LLVM::LoadOp` gained builder arguments;
  - `cl` options can now be per context;
  - the debug-intrinsic APIs were removed.

  0002 adds LLVM consumers that the survey did not read, so the next
  survey covers them too:
  - googletest and googlemock from `third-party/unittest`
    (`foreign/idr/unittests`);
  - compiler-rt's `FuzzedDataProvider.h` (`tests/toolchain/lib`);
  - `PassInstrumentation` (`lib/Transforms/Contracts`);
  - `DialectReductionPatternInterface` (`tools/idris-mlir-reduce.cpp`).
- **Behaviour the suites judge:**
  - scf-to-cf's non-wrapping increment (9e00863f);
  - remove-dead-values' poison for dead arguments (0edf6243);
  - bufferization (5e248845, d2146051);
  - arith-to-llvm (a5d2f05b, dd0c1922);
  - scf peeling of the first iteration (fa1e20e8, 15106899), where the
    schedule peels the last.

## Idris 2

Main (89ba32eb) is two commits past the gitlink, and neither touches
`src/`. b6cbc25d makes `Data.Vect.fromList` structural. 89ba32eb gives
five buffer primitives a `RefC:` spec.
- **The fork** takes nothing. A re-sync moves only its recorded base:
  `idrisVersion` in `compiler/idris/src/IdrisPaths.idr`, and
  `compiler/idris/README.md`. Every fork fix's `pull-request.diff`
  applied cleanly to 89ba32eb (*measured*). The fork's own files since
  then, such as 0002's `Idris/Host.idr`, touch none of upstream's files.
- **Base** arrives with the gitlink (`make prefix`), and changes nothing
  for us:
  - the registry matches a `%foreign` definition by any spec it knows
    (`declares`, `compiler/src/IdrisMLIR/Registry.idr`), so the new
    `RefC:` specs resolve as before;
  - the registry names no `Data.Vect` function.
- **The stock Idris** that the bootstrap builds carries no
  `idris.patch`.

## CMake and Chez

- **CMake 4.4.4.** The lock's `cmake` entry moves: revision 2e0b3aec,
  the tag, the version, and `accept: "4.4"`, which the gate in
  `CMakeLists.txt` reads. Nothing else changes:
  - `cmake_minimum_required(VERSION 4.0)` keeps the new policies of 4.3
    and 4.4 (CMP0205 to CMP0219) at their old behaviour;
  - neither release's deprecations are used;
  - presets schema 8 stays valid;
  - the bootstrap's `./bootstrap` and its version check work unchanged.
- **Chez.** Main is "10.5.0-pre-release.1", 24 commits past v10.4.1. It
  includes W^X support (00772bf, 5ee2152), which arm64 macOS benefits
  from. No `chez.patch` is carried. Chez moves when 10.5.0 is tagged.

## Order

1. `make self` is green on both targets, on the current pins.
2. **Idris 2, alone** (it rebuilds no LLVM). Move the gitlink and the
   fork's recorded base. Then, on both targets: `tools/bootstrap.sh
   idris`, `make fork`, `make build`, `make test`, `make self`.
3. **CMake and LLVM together**, so that LLVM is rebuilt once.
   - Run the survey above again.
   - Make one commit: the lock's `cmake` and `llvm` entries, the reworked
     06 and 07, the 01 retirement and 06's new condition.
     `tests/spec/upstream-patches` checks the patches.
   - On both targets, run `tools/bootstrap.sh cmake llvm`, every check
     AGENTS.md names, and `make self`. Then regenerate the typecheck
     build (`make typecheck`).
4. **The PINS.md tombstone sweep**, against the new pins.

## Decisions

- Idris goes first and alone, then CMake with LLVM (*decision*: LLVM's
  build is the cost, so it is paid once).
- Chez takes releases only (the pin policy).
- **The ryu pin is the owner's question.** ryu has made no release since
  v2.0 (2019), and the pin is 108 commits past it. The policy's "latest
  release" would mean moving back to v2.0. The default is to stay at
  4c0618b until the owner decides.
