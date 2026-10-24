<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Third parties in what we ship

Every program this compiler makes is statically linked,
so distribution is the act that matters: this file names every
third party whose code reaches a shipped binary, its license, and
where its text lives. It is kept by the same change that adds or
moves a pin (PINS.md records the pins).

| Part | Used as | License (SPDX) | Text |
| --- | --- | --- | --- |
| snmalloc | the runtime's allocator | MIT | `third_party/snmalloc/LICENSE` |
| ryu | float printing in the runtime | Apache-2.0 OR BSL-1.0 | `third_party/ryu/LICENSE-Apache2`, `LICENSE-Boost` |
| fast_float | float parsing in the runtime | Apache-2.0 OR MIT OR BSL-1.0 | `third_party/fast_float/LICENSE-*` |
| simdutf | UTF work in the runtime | Apache-2.0 OR MIT | `third_party/simdutf/LICENSE-*` |
| GMP | big integers (`%lib`-free: the runtime's `idr.big`) | LGPL-3.0-or-later OR GPL-2.0-or-later | `third_party/gmp/COPYING*` |
| LLVM/MLIR (pinned toolchain) | linked into our tools; runtime bitcode joins programs | Apache-2.0 WITH LLVM-exception | `LICENSES/Apache-2.0.txt`, `LICENSES/LLVM-exception.txt` |
| Idris 2 (`third_party/Idris2`, unmodified pin) | host side only: builds the checker and the frontend | BSD-3-Clause | `third_party/Idris2/LICENSE` |
| Chez Scheme (pinned toolchain) | host side only: runs Idris 2 and the test runner | Apache-2.0 | the pin's tree under `.toolchain/` |

One entry is not permissive: **GMP**, which we take under
LGPL-3.0, not GPL-2.0. The runtime calls it for `Integer` (30 entry
points, all behind `runtime/Big/` and `runtime/Alloc/Gmp.cpp`), and it
enters every link as a static archive, never as bitcode, so a shipped
compiler carries it, and so does every program that uses `Integer`.
LGPL-3.0 §4 lets such a combined work go out under our terms with its
notice and the GPL and LGPL texts, and one of: the application in a
form the user can relink against a modified GMP (§4(d)(0)), or a shared
library (§4(d)(1)), which AGENTS.md's static linking rules out.

The default, until the owner decides with counsel: GMP stays, statically
linked, and a shipped binary meets §4(d)(0) with a relink kit. For a
program, the kit is the archive `idris-mlir -c` writes (one object per
codegen bin, in bin-name order), the prepared runtime object
(`--print-runtime`), the rest of the link line with GMP in it
(`--print-link-flags`), and GMP's source at the pin. For a compiler
release, it is the static libraries and the final link command its
build already writes. The notice and both license texts travel beside
the binary. Nothing is owed while the repository ships source alone:
`tools/bootstrap.sh` and `make` build every binary on the user's machine.

Open, for the owner with counsel: whether that kit is acceptable for the
binaries he means to ship (a compiler release, programs, and the
programs users build and ship), or whether GMP must go. If it goes, a
permissive bignum takes its place behind `runtime/Big/`'s interface, the
only code that calls GMP, chosen in a proposal of its own.
