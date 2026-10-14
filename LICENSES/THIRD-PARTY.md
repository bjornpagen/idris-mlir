# Third parties in what we ship

Every program this compiler makes is statically linked,
so distribution is the act that matters: this file names every
third party whose code reaches a shipped binary, its license, and
where its text lives. It is kept by the same change that adds or
moves a pin (PINS.md records the pins).

| Part | Used as | License (SPDX) | Text |
| --- | --- | --- | --- |
| musl | the target's libc (Linux sysroot) | MIT | `third_party/musl/COPYRIGHT` |
| snmalloc | the runtime's allocator | MIT | `third_party/snmalloc/LICENSE` |
| ryu | float printing in the runtime | Apache-2.0 OR BSL-1.0 | `third_party/ryu/LICENSE-Apache2`, `LICENSE-Boost` |
| fast_float | float parsing in the runtime | Apache-2.0 OR MIT OR BSL-1.0 | `third_party/fast_float/LICENSE-*` |
| simdutf | UTF work in the runtime | Apache-2.0 OR MIT | `third_party/simdutf/LICENSE-*` |
| GMP | big integers (`%lib`-free: the runtime's `idr.big`) | LGPL-3.0-or-later OR GPL-2.0-or-later | `third_party/gmp/COPYING*` |
| LLVM/MLIR (pinned toolchain) | linked into our tools; runtime bitcode joins programs | Apache-2.0 WITH LLVM-exception | `LICENSES/Apache-2.0.txt`, `LICENSES/LLVM-exception.txt` |
| Idris 2 (`third_party/Idris2`, unmodified pin) | host side only: builds the fork and frontend | BSD-3-Clause | `third_party/Idris2/LICENSE` |
| Chez Scheme (pinned toolchain) | host side only: runs Idris 2 and the test runner | Apache-2.0 | the pin's tree under `.toolchain/` |

One entry is not permissive: **GMP**. Static linking against an
LGPL-3.0 library carries relinkability and notice obligations that
a static PIE does not obviously satisfy in the usual way. This
predates the inventory and nothing here changes it; it is named
for the owner to settle with counsel, and until
then it is carried visibly, not implicitly.
