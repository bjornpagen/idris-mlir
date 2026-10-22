<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Notes for INT, kept by the coordinator

Things no lane owns that INT must do before it builds. Each lane's
handoff lists its own wiring.

- **Submodule checkouts lag their gitlinks.** The coordinator moved the
  gitlinks without fetching, so the commits are not yet local:

  | submodule | checkout | gitlink |
  | --- | --- | --- |
  | `third_party/Idris2` | 1c630e67c | 89ba32eb |
  | `third_party/modular` | 9211931 | a1ccd095 |
  | `third_party/simdutf` | bb77e7bb (9.3.0) | 8d82299 (9.3.2) |

  Run `git submodule update --init --recursive` (it fetches) before
  anything builds. The bootstrap's simdutf step refuses a mismatch.
- **Generated outputs.** Run specgen and commit every output listed in
  `generated.manifest`, the manifest included. L16 deleted the stale
  `compiler/src/IdrisMLIR/{Dialect,Encoding}/Idr.idr`, which specgen
  writes again. L19 wrote `Expect/Properties.inc` by hand to match its
  records; the printer must reproduce it.
- **The fork's TTC version** needs bumping if L17's changes alter the
  TTC (L17b).
- **Per D111:** build the Idris half here on stock Idris, route its
  errors, and stop at the LLVM build. The owner runs the bootstrap and
  the C++ build on the four targets.
- **Qualification, added by L11:** re-measure code generation
  time on the large-function program that set `inlineCallerInstructions`
  (recorded 2.8 s against 95 s), since always-inline runtime entries now
  inline into large functions too (C186). L11's guess is a small cost,
  unmeasured.
- **Admitted classes (L06, 2026-10-22):** nothing in CMake runs
  `-gen-admitted-classes` yet; wire it. After specgen `write`, run
  `tools/dialects.sh generate`, which now reads each dialect's
  `Generated/IdrAdmitted<Name>.td`; the Idris dialect modules then hold
  only admitted ops' builders.
- **Stale generation in CMake (L11, 2026-10-22):**
  `foreign/idr/include/idr/IR/CMakeLists.txt` lines 9-12 and 23-28
  still run tblgen backends that no longer exist (`IdrRules.txt`,
  `IdrRuleCategories.inc`, `IdrPassRoles.txt`, `IdrPassStages.txt`).
  `idris-mlir-tblgen` registers only `gen-idris-syntax`,
  `gen-idris-dialect`, `gen-idris-bytecode` and `gen-admitted-classes`.
  Delete those lines. The `lib/` CMakeLists also name about 91 deleted
  sources (the C2 audit's count); rewire every list from the handoffs.
