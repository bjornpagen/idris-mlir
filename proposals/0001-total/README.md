<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0001: total by construction, every known item, and upstream's TODOs

**Status:** integrated 2026-10-15 (d06ed15c), typecheck only. There,
`make typecheck` passed every part and `make check` passed 33 of 33
(*measured* on the typecheck machine). Nothing of it has been built or
run, and nothing has run on a build machine since c7aa7b62. What remains
is the build (§2), which self-hosting needs; every other item it left has
a home or is named as having none (§3). This file is deleted when the
owner's build is green. The wave's full record is this file at b843d8b5:
the C++ style it wrote by, what it built by area, the rulings, the
verification, the bugs review found and fixed, and the trust left.
0002's dispatches cite that text by section. Claims are marked *read*
(the path), *measured*, *recalled*, *conjecture*, *decision*.

## 1. What it built (*read* at each path; typechecked, never built)

- No fuel in the C++: `idr::OnceWorklist` and `idr::MonotoneWorklist`
  (`foreign/idr/include/idr/Support/Worklist.h`), `TailPaths`
  (`lib/Conversion/TailPosition.cpp`), `idr-canonicalize`'s
  `not-converged` and `test-convergence` (`Transforms/Passes.td`), the
  size policies in `tools/policies.txt`, held by `tests/spec/no-fuel`.
- The frontend `%default total`, the reduction on the walk
  (`Frontend/Walk.idr`), a nested data type refused
  (`tests/reject/polymorphism-nested-data`), `Linear.Vec` size-indexed
  (`libs/mlir-array/Linear/Vec.idr`).
- Instance finiteness proved on base alone (`compiler/src/IdrisMLIR/Proof/`,
  `Finite.chainsEnd`).
- The fork total on the frontend's paths, `%totality_depth` refused,
  the size-change decision on typed paths
  (`tests/compiler/fork-loops-terminate`), four of Idris's bugs fixed as
  fork code (`upstream/fork-*`, PINS.md).
- Dozens of null, sentinel and flag states made unrepresentable in the
  C++ (b843d8b5 §3.5 to §3.10); specialization lifts a key's scalars
  (*decision*, argued at the head of
  `lib/Transforms/Specialize/Specialize.cpp`).
- Patch 24 analyzes cycles of calls and carries what was 26
  (`upstream/24-one-shot-module-function-interface`); 27, 48 and 49 are
  submissions; `idr.element.update` (`IR/IdrArrayOps.td`).
- The runtime's cleanup and speed pass: every OS call behind
  `rt::platform` (`runtime/Platform/Platform.h`), the simdutf kernel
  chosen by the startup check, the even-group free fixed
  (`tests/idr/e2e/even-group.mlir`), `<build>/runtime/c-flags`
  (`runtime/CMakeLists.txt`).
- 0016's L5 and L6 (`tools/licenses.sh`); modular a reference submodule
  (`.gitmodules`); simdutf v9.3.0 and fast_float v8.3.2
  (`toolchain.lock.json`). The C++ grew about 3,500 lines net
  (*measured* at d06ed15c).

Its rules live where they apply: no fuel and a budget that never refuses
in AGENTS.md and `tools/policies.txt`, a linear value used at most once
in `IR/Verify.h` (`linearity`), the caller's CPU count in `tools/host.sh`,
the pin policy in AGENTS.md.

## 2. What remains: the build (SELF-HOST)

`make self` starts from a tree that has passed the suites, and this tree
has never been built. 0002 integrates first (0002 §0), so the owner's
next build covers both. HANDOFF.md holds the steps:
- `make bootstrap`, because patch 24 and the simdutf and fast_float pins
  changed since the last build;
- `make build`, which reconfigures and so writes the `c-flags` that the
  toolchain tests compiling against `idris_rt.h` read;
- `make test`, `make test-idr` and `make test-mlir-tools` on both
  targets;
- every file `tests/ACCEPTANCE.md` lists, accepted.

Beyond those files, the build settles two conjectures:
- the generated dialect printers print the same text, now that they
  recurse on an abstract `Spelling`;
- the fork's TTC decoders read and write the same bytes and hashes, now
  that they recurse on the bytes left.

## 3. Where the rest went

Each item of the old §5 (b843d8b5), with its home:

1. **The build and acceptance.** §2 above, and HANDOFF.md.
   **SELF-HOST.**
2. **The toolchain bump.** [0005-toolchain-bump.md](../0005-toolchain-bump.md), after
   `make self`. **AFTER-SELF.**
3. **A chain that grows once and stops is refused.** The owner's ruling
   (47f97059), recorded in 0014's feature 2. Decided.
4. **The dictionary passes.**
   - Their `assert_total` goes in 0002's lane Q. Idris-mlir refuses a
     user module's assertion, and `IdrisMLIR.*` is the project's
     (`Registry/Libraries.idr`, `assertion`, `moduleOrigin`).
     **SELF-HOST**, in 0002. The live tree has outcome B:
     `covering translateFrom`.
   - Their proof has no home: the request tree as a value before the
     passes, then a pigeonhole measure. Q names it with 0011's O3, which
     does not yet hold it. **AFTER-SELF.**
5. **The rest of Host.** 0002's lane I moves `Host` and its one
   `assert_total` into the fork (live:
   `compiler/idris/src/Idris/Host.idr`). **SELF-HOST**, in 0002. The
   trust itself stays while Idris's theory is not strongly normalizing.
   Nothing else remains.
6. **The translation of applications, total.** 0002's lane T, with
   `normaliseHoles` in place of `normaliseAll` (0002 §4.6). It keeps the
   owner's ruling (47f97059): an implementation that refers to a
   definition Idris does not prove total is refused. Both hosts admit
   `covering`, so self-hosting does not wait on it. **AFTER-SELF**,
   though it is in 0002.
7. **The deferred designs.** Each is **AFTER-SELF**, and none has a
   home:
   - data-type bodies that hold buffers. The design deletes `DataRemap`'s
     buffers remap; it is at b843d8b5 §5 item 7, and 0009 does not hold
     it.
   - carrying a `rewrite`'s equality into MLIR. It was named for 0009's
     stages 2 and 5, and neither holds it.
   - a vectorizer gather from a memref: upstream work, once a program
     needs one.

   The canonicalizer cases a fold weakens need nothing: the driver's next
   sweep sees them (`include/idr/Transforms/Canonicalize.h`).
8. **Strings that stand for things.** 0002's lane I takes the frontend's
   and Emit's tables. **AFTER-SELF.** No home:
   - typed SSA names (Emit's `names`, Bytecode's numbering), which lane I
     names as later work;
   - the C++'s: `CalleePattern::kLabel` (`include/idr/IR/Canon.h`,
     `lib/IR/Canon/Callees.cpp`), the runtime table's `StringMap`s
     (`lib/Conversion/Runtime.cpp`), and `getName() == "main"`
     (`lib/Driver/Run.cpp`).
9. **The primitives.** 0002's lane P deletes the `scalar_end` chain,
   makes the UTF-8 step one primitive, and audits the registry, ODS and
   runtime as one list. No home: stock-host meanings for `prim__scalarAt`
   and `prim__dropBytes`, which P names as later work. **AFTER-SELF.**
10. **A pass to trim the C++.** No home. **AFTER-SELF.**
11. **The submissions ready to file.** The owner's; `upstream/README.md`'s
    table is the list. **AFTER-SELF.**
12. **The ryu pin.** The owner's question, moved to 0005-toolchain-bump.md.
    **AFTER-SELF.**
