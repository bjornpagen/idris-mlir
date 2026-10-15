<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The toolchain bump after this wave

Prepared 2026-10-15, read-only. Nothing was built, nothing filed, and
nothing was sent to Idris. The pin policy: the LLVM umbrella projects
(llvm-project), Idris 2 and modular track main; every other dependency
(Chez Scheme, CMake, Ninja, musl, GMP, simdutf, fast_float, snmalloc)
takes its latest release. Every check ran in a blobless scratch clone
under /tmp; nothing touched `.toolchain` or `third_party`.

| Tool | Pinned | Newest | Verdict |
|---|---|---|---|
| llvm-project | main 7208ba24 | main 7a83be39 (contains b1fa48e7) | bump: rebase one patch, refresh another, no C++ change |
| Idris 2 | 1c630e67 (v0.8.0-105) | main 89ba32eb (2 commits later) | bump: base only; the fork and its fixes are unaffected |
| Chez Scheme | v10.4.1 (e95a7efb) | v10.4.1 (main is a 10.5.0 pre-release) | stay: Chez takes its latest release; move when 10.5.0 is tagged |
| CMake | v4.2.8 | v4.4.4 (2e0b3aec); 4.5.0-rc1 | bump to 4.4.4: the gate's series moves, nothing else |
| Ninja | v1.13.2 | v1.13.2 (master is 202 commits on, untagged) | stay |

## LLVM

- From: the pin, 7208ba24 (`llvmorg-24-init-13225`).
- To: main at 7a83be39 (2026-10-15 15:31Z). That is 1253 commits past
  the pin, so `git describe` should give about
  `llvmorg-24-init-14478-g7a83be39`; confirm it before writing the lock.
  Still LLVM 24.0.0, so the lock's `accept: "24"` holds.

### Carried patches (`upstream/*/llvm.patch`)

Each patch was checked alone with `git apply --check`, then in name order
on a copy of the files the patches touch, as `tools/bootstrap.sh` applies
them.

| Patch | Against 7a83be39 | Upstream since the pin | Needs |
|---|---|---|---|
| 03 bytecode-deferred-quadratic | clean | no; open #229910 overlaps it | nothing |
| 04 vectorize-precondition-body | clean | no (56e57d4e is NFC) | nothing |
| 05 forward-dataflow-callee-lookup | clean | no | nothing |
| 06 remove-dead-values-unreachable | **conflicts** in its function-argument hunk (`cleanUpDeadVals`, pin line 652) | in part: #208881 (0edf6243) gives dead function arguments' uses `ub.poison` | a rebase: drop that hunk, since main does the same, or route main's loop through the patch's `replaceUsesWithPoison`. Without the hunk it applies, alone and after the rest. Redo its PR text and its comment on #208881. |
| 07 inline-unreachable-terminator | offset (4 to 15 lines; d8b7bd11 changed Inliner.cpp) | no | refresh it so it applies with no offset |
| 09 int-range-narrowing-exactness | clean | no | nothing |
| 19 pass-timing-dynamic-pipeline | clean | no; #169615 is still open | nothing |
| 23 cse-statistic-assignment | clean | no | nothing |
| 24 one-shot-module-function-interface | clean, checked before 26 was folded into it; 26 alone was clean too (5e248845 touches another function of OneShotAnalysis.cpp) | no | check the folded patch again |

Taken in order (with 06 skipped, then 06 without its function-argument
hunk applied last), all of them apply.

The submissions the bootstrap does not apply (`pull-request.diff`): 02,
08, 16, 17, 22 and 25 apply cleanly to 7a83be39, and 27 applies with an
offset. None of their bugs is fixed on main, so their `tests/upstream`
checks keep saying "still reproduces". 48 and 49 are patches to simdutf
and snmalloc, not LLVM.

What retires with the bump:
- PINS `remove-dead-values-address-taken` (01) and
  `tests/upstream/remove-dead-values-address-taken`. The entry's retire
  condition is "the pin has #208881". Per upstream/README.md, a build of
  #208881's change alone on 2026-10-08 fixed 01's test. 01's report stays
  as the test-only PR, since #208881 landed without that case.
- PINS `remove-dead-values-unreachable` (06) stays, its retire condition
  reworded to "the pin has the rebased PR".

### API changes our C++ meets

All of foreign/idr/** and runtime/** (there is no tools/*.cpp) was
checked. None of the 277 LLVM and MLIR headers they include was removed.
Nineteen of them changed; every change was read. **No code change is
needed.**

| Change on main | Commit | Our use | Effect |
|---|---|---|---|
| `llvm::TimeTraceScope` is `[[nodiscard]]` | 2ac1d901 | idr/Support/Profile.h:75 names the scope as a variable | none |
| TableGen keeps classes and defs in a `StringMap`; RecordVal internals moved | 80017ba1, f4095d22, 6a6c90e1, b4effb25 | tools/idris-mlir-tblgen.cpp: `getAllDerivedDefinitions[IfDefined]` (:327, 981, 994, 1686, 1693, 1714, 1973, 2107, 2151) and the `getValueAs*`/`getValue`/`getDef`/`isSubClassOf` accessors | all still there; `getAllDerivedDefinitions` still sorts with `LessRecord`, so the generated files keep their order |
| `LLVM::LoadOp` builder gains `isNoundef` after `isInvariantGroup`; the op gains `noundef` and `range`; `AtomicRMWOp` gains a trailing `ignoreDenormalMode` | a0957bb8, 2d97a34c, 14915087 | Conversion/RuntimeCells.cpp:66, 74, 93, 103; Buffers.cpp:43; PassThroughMemory.cpp:85 pass at most the alignment | none |
| Library options can be per `LLVMContext`; new `cl::parseCommandLineOptions` | d7316136 | Driver/Main.cpp:146 calls `cl::ParseCommandLineOptions` | none: it still sets the global values, which a context without its own reads |
| `PrintPipelinePasses` moved into `PassBuilder` | 16dae0f2 | unused | none |
| `createNullTargetStreamer` is fatal for a target without one | 44a08dc7 | no null streamer | none |
| Debug-intrinsic APIs removed (BasicBlock.h, Instruction.h, IntrinsicInst.h, DebugInfo.h) | 7159ce54, 90a26c2f, 2b35fb92, 79005f6c | unused | none |
| `mlir/Conversion/ArithCommon` renamed `ArithAttrToLLVM`; `MLIRRemarkStreamerBase::createToFile` returns `Expected` | 80c5d732, 51645748 | not included | none |

The vector transform ops the schedule names exist unchanged. Every other
MLIR header change we include is an addition.

Behaviour changes on passes our pipeline runs. Expected output may move;
the suites decide:
- 9e00863f: scf-to-cf marks an scf.for's increment as non-wrapping.
- 0edf6243: remove-dead-values gives dead function arguments' uses
  `ub.poison`, the same as 06 already does at the pin.
- 5e248845 and d2146051: bufferization.
- a5d2f05b and dd0c1922: arith-to-llvm.
- fa1e20e8 and 15106899: scf front peeling. The schedule peels the last
  iteration, not the first.

## Idris 2

Main (89ba32eb, 2026-10-14) is two commits past the gitlink (1c630e67),
and neither touches `src/`:
- b6cbc25d (`libs/base/Data/Vect.idr`, perf): `Data.Vect.fromList`
  becomes structural recursion, with no `rewrite` and no `reverse`, so
  that upstream's back ends erase it.
- 89ba32eb (`libs/base/Data/Buffer.idr`): five buffer primitives gain a
  `RefC:` spec beside their `scheme:` one.

What this means for us:
- **The fork (compiler/idris/src).** Upstream changed nothing it
  carries. There is nothing to take, and nothing collides with T3's
  totality work. A re-sync changes only the recorded base: the commit in
  `compiler/idris/src/IdrisPaths.idr:12`
  (`idrisVersion = ((0,8,0), "1c630e67c")`) and compiler/idris/README.md.
- **The fork's fixes.** None of their bugs is fixed upstream, so every
  fix stays. Each `pull-request.diff` applies cleanly to 89ba32eb:
  fork-build-main, fork-interface-body, fork-linear-ambiguous-let,
  fork-total-frontend-paths, fork-totality-depth,
  fork-with-application-scope, 18, 20 and 21.
- **The frontend's prelude and base.** `make prefix` builds them from
  third_party/Idris2/libs, so both base changes arrive with the gitlink.
  - The registry matches a `%foreign` definition when any of its specs
    is a known one (`declares`, compiler/src/IdrisMLIR/Registry.idr:56).
    The new `RefC:` specs name no entry, so the buffer primitives resolve
    as before.
  - `Data.Vect.fromList` compiles to a different, structural
    definition. The registry names no Data.Vect function.
- **The stock Idris the bootstrap builds** (stage 0: the fork, the
  frontend, the test runner). No `upstream/*/idris.patch` is carried, so
  there is nothing to refresh. It takes the same base change.

## Chez Scheme

No `upstream/*/chez.patch` is carried. Main is 24 commits past v10.4.1
and calls itself "10.5.0-pre-release.1". Its submodules (lz4, nanopass,
stex, zlib, zuo) are at the same commits.

What it changes for the Idris host:
- Better support for W^X hosts (00772bf, 5ee2152). arm64 macOS is one.
- A fault outside Scheme code goes to the handler installed before
  (41d5ffc).
- Compiler loop detection (e3b1363) and faster floating point (879f29e,
  d9e76eb).
- A fix for large immobile bytevectors (7fbf1c0).
- `log1p`'s precision and `(lcm 0 x)` (35c2f4b, 8d10590).
- The armv7 machine rename touches neither `ta6le` nor `tarm64osx`.

Chez takes releases only, so nothing moves until 10.5.0 is tagged; the
changes above arrive with it.

## CMake and Ninja

CMake 4.4.4 against our CMake and bootstrap:
- **The gate.** `CMakeLists.txt:29` accepts exactly the lock's series,
  so the lock's `cmake.accept` becomes `"4.4"` with its revision, tag and
  version.
- **Policies.** `cmake_minimum_required(VERSION 4.0)` keeps every policy
  4.3 and 4.4 add (CMP0205 to CMP0219, among them macro backslashes and
  one file per file set) at its old behaviour.
- **Deprecations.** The ones in 4.4 (`-Wdev`, `--warn-uninitialized`,
  `--no-warn-unused-cli`, `CMAKE_WARN_DEPRECATED`, the `MACROS`
  property) and 4.3 (`CMAKE_ENABLE_EXPORTS`) are not used by the presets,
  the CMakeLists or the bootstrap.
- **Presets.** Schema 8 stays valid.
- **The LLVM build.** It is configured by the same CMake, and LLVM's
  minimum (3.20) is within 4.x's compatibility.
- **The bootstrap.** It builds CMake with `./bootstrap` and checks
  `cmake version <version>`, which works for 4.4.4 unchanged.

Ninja 1.13.2 is the newest release; nothing moves.

## Order

1. Land this wave green on the current pins.
2. **Idris 2.** Do this alone: it rebuilds no LLVM.
   - Move the gitlink to 89ba32eb.
   - Update the fork's recorded base (IdrisPaths.idr:12, compiler/idris
     README).
   - `tools/bootstrap.sh idris`, then `make fork`,
     `make build` and `make test` on both targets.
3. **CMake 4.4.4 and LLVM 7a83be39 together**, so that LLVM is rebuilt
   once.
   - Rebase 06 and refresh 07; the other patches stay byte for byte, and
     `tests/spec/upstream-patches` against the new revision is the check.
   - In one commit: the lock's cmake and llvm entries, the reworked
     06 and 07, the 01 retirement and 06's reworded retire condition.
   - On both targets: `tools/bootstrap.sh cmake` and `llvm`, then
     `make build`, `make test`, `make test-idr` and `make test-mlir-tools`,
     and regenerate the typecheck build (`make typecheck`).
4. The PINS.md tombstone sweep against the new pins.
