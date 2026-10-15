<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0001: licensing: every file says whose it is

**Status:** decided by the owner 2026-10-14. The policy is built
(3a275cf0, L1 to L4): the root `LICENSE` and `NOTICE`; `LICENSES/`,
which holds every text and `THIRD-PARTY.md`, the inventory of what
reaches a shipped binary; the SPDX line on every in-scope file of ours
and of the fork; `tools/licenses.sh`, which holds the sweep's scope and
writes the lines; and its gate, `tests/spec/licenses`.
`foreign/README.md` states the porting protocol. One port has landed:
Modular's `EliminateDuplicateFunctions.cpp` at `9211931`, Apache-2.0
WITH LLVM-exception, as
`foreign/idr/lib/Transforms/Deduplicate/EliminateDuplicateFunctions.cpp`,
its header kept and its PINS.md entry `eliminate-duplicate-functions`
written. L5 and L6 were built in 0004 (§1, §2), on the typecheck
machine, where the sweep's `--apply` runs at integration and
`tests/spec/licenses` then proves them in `make check`; x86_64 Linux is
NotRun. What remains is the owner's: accepting the built state; §3's
GMP question, with counsel, its default taken; and §4's open question
on a port's changes note, its default taken. This file is deleted when
the owner accepts the built state; §3's default and question then live
in `LICENSES/THIRD-PARTY.md`'s GMP paragraph, which already states both.
Claims are marked: *read* (the path), *measured*, *recalled*,
*conjecture*, *decision*. It is not legal advice, and the one item that
needs a lawyer's eye is named as such in §3.

## 1. L5: the generator writes its own line

Built in 0004 (*decision*, D6). `idris-mlir-tblgen` writes the `0BSD`
line and the copyright line at the top of every generated dialect
module (`compiler/src/IdrisMLIR/Syntax/` and `Dialect/`, checked by
`tests/spec/dialects-current`), so committed generated files carry the
line their generator writes, and `tools/licenses.sh` lists no exclusion
for them. Build-tree generated files are out of scope.

## 2. L6: the scope is the tree, and the gate reads its facts from data

Built in 0004 (*decision*, D3, D4, D9, D10), in `tools/licenses.sh`,
which `tests/spec/licenses` runs (*read*):
- **The scope is every file git tracks or would track,** less one
  listed exclusion set, each exclusion with its reason (the other
  parties' trees, bytes a test or a record compares or quotes, files
  with no comment syntax), so a file of a new kind is in scope at once
  and named until its kind's comment syntax is known. The line is
  written in each kind's comment syntax.
- **A fork file's holder is read from the pin:** upstream's for a file
  the pin's `src/` has, ours for any other, under BSD-3-Clause as the
  whole fork is (D3), so the integration's `--apply` makes
  `Libraries/Data/Table.idr` and `IdrisPaths.idr` name us.
- **The required license texts are derived from the identifiers in
  use,** a file of several provenances naming them in one compound SPDX
  expression (D4).
- **A port's attribution is checked by its part:** Modular's copyright
  line for a Modular port, LLVM's "Part of the LLVM Project" line for an
  MLIR/LLVM port, the part its PINS.md entry names.

## 3. The inventory and the GMP question

`LICENSES/THIRD-PARTY.md` names every pin and submodule that
reaches a shipped binary, its license, and what the binary therefore
carries; it is kept by the same change that adds or moves a pin.
0013's crate graph, when it is unparked, enters it by the same rule.
GMP is its one non-permissive entry.

**What reaches a binary** (*read*). The runtime calls GMP for `Integer`:
29 distinct `mpz_` functions and macros (and the types `mpz_ptr`,
`mpz_srcptr`), all in seven of `runtime/Big/`'s eight files, plus
`mp_set_memory_functions`, which routes GMP's allocation through ours
(`runtime/Alloc/Gmp.cpp:35`); 30 entry points in all (grep). The bigs'
own interface is `runtime/Big/Big.h`, and `runtime/Big/` is 526 lines
(`wc`). GMP enters every link as a static archive on the link line,
never as bitcode: `-lgmp` from the musl sysroot on Linux, the sysroot's
`libgmp.a` on macOS (`CMakeLists.txt:175, 219`); what joins a program's
module as bitcode is our runtime, not GMP. Our tools link the runtime
too, because folders call it, and the runtime's interface links GMP
(`runtime/CMakeLists.txt:223-224`; `foreign/idr/CMakeLists.txt:113`), so
a shipped compiler carries GMP as well as every program it makes.
Whether a program that never uses `Integer` carries any GMP code is
*conjecture*: an archive links only the members a reference pulls, and
the driver internalizes the runtime and runs O3 before the link, so none
is expected. `llvm-nm` on such a program's executable settles it at the
owner's machine's first build of the tree after the pipeline cutover
(c7aa7b62, 5d5f3312; its proposal at 484d6403), which has not yet run;
the kit below is owed only by a binary that contains GMP. The repository
distributes source only: `tools/bootstrap.sh` and `make` build every
binary on the user's machine, so nothing is owed by us until a binary
ships.

**The terms** (*read*, `third_party/gmp/COPYING.LESSERv3:79-126`). We
take GMP under LGPL-3.0, not GPL-2.0. §4 lets a combined work be
conveyed under our terms with notice (a), the GPL and LGPL texts (b),
and one of: (d)(0), the application in a form that lets the user
relink it against a modified GMP, or (d)(1), a shared library. AGENTS.md
forbids a third party's shared library, so (d)(1) is closed and (d)(0)
is the only route. §4(c) applies only to a work that displays copyright
notices while it runs, which neither the tools nor the programs do;
§4(e)'s installation information is owed only where GPL §6 would ask
for it, for a user product, which a compiler release is not. Our own
terms (0BSD) restrict neither modification nor reverse engineering, as
§4's opening asks. Small inline material from `gmp.h` (`mpz_sgn` and
the like) is allowed by §3 (`:63-77`).

**The default** (*decision*, until counsel answers): GMP stays,
statically linked, and a shipped binary meets LGPL-3.0 §4(d)(0) with a
relink kit. For a program: the archive `idris-mlir -c` writes, one
object per codegen bin in bin-name order (the cutover's D32, which names
this kit; `-c` is `foreign/idr/lib/Driver/Options.cpp:24-29`), the
prepared runtime object (`--print-runtime`), the link line's remaining
arguments with GMP among them (`--print-link-flags`,
`Options.cpp:105-113`), and GMP's source at the pin. For a compiler
release: the static libraries and the final link command its build
already writes (*conjecture*: no new code, since CMake links the tools
from those archives). In both, the notice and the two license texts
travel beside the binary. Reasons: the link already has this shape
(separate objects, GMP an archive, the link line printable), so the
default costs no code; replacing GMP costs a bignum implementation and,
*conjecture*, asymptotic speed: `pidigits` at 10,000 digits runs at
0.66x of its C, both over GMP (clang 0.445 s against ours 0.669 s,
`bench/runs/2026-10-13-9a1b7b1-darwin-arm64/results.md:31`,
`bench/c/pidigits.c:3`, *measured*), and a schoolbook replacement would
widen that gap; and no binary ships today. Every user who ships a
program this compiler made inherits the same obligations, which the kit
is what makes possible.

**Open, for the owner with counsel:** whether §4(d)(0) by a relink kit
is acceptable for the binaries he intends to ship (a compiler release,
programs, and programs users build and ship), or whether GMP must go.
Default: the kit above. If the answer is "GMP goes", the replacement
is a permissive bignum behind `runtime/Big/`'s interface, the only code
that calls GMP, chosen in its own proposal by `pidigits`' ratio to its
C. Candidates, *recalled* and to be read there: libtommath (public
domain or Unlicense), imath (MIT), and LLVM's `DynamicAPInt` (in the
pinned tree at `.toolchain/llvm-project/llvm/include/llvm/ADT/DynamicAPInt.h`,
Apache-2.0 WITH LLVM-exception, already in our license set; its
multiplication algorithm is *recalled* as schoolbook). Nothing here
delays identifiers.

## 4. Decisions (the record)

- D1 (owner, 2026-10-14): the policy (what we write is ours, 0BSD; a
  port keeps its license, its copyright and every header block, and
  gains an SPDX line and a changes note; vendored third parties stay
  unmodified submodules), its identifiers, the porting protocol and the
  inventory. Built (3a275cf0): `LICENSE`, `NOTICE`, `LICENSES/`,
  `foreign/README.md`, `tools/licenses.sh`, `tests/spec/licenses`.
- D2: the root text is `0BSD`, by template match. Built.
- D3: one license per tree for the fork; new fork files are ours under
  BSD-3-Clause, and which fork files are new is read from the pin (§2).
  Built in 0004.
- D4: a port keeps every header block; a file with several provenances
  names them in one compound expression of SPDX list identifiers, and
  their texts join `LICENSES/`. Reason: Modular's tree has such files
  (LLVM's bitcode writer copies under
  `Mojo/lib/Compiler/ObjectCompiler/LLVM/Bitcode/` keep LLVM's SPDX
  line nested below Modular's header, and `ConcurrentMPMCQueue.h` nests
  a BSD-2-Clause notice, *read* at `9211931`).
- D5: a rebuild is ours, names its design in comments without a path,
  and names path and revision in its commit message; copied text makes
  a port, whatever the line count.
- D6: committed generated files carry their generator's line; the
  generated-module exclusion goes (§1). Built in 0004.
- D7: GMP's default is LGPL-3.0 §4(d)(0) by a relink kit, whose program
  half is the archive `-c` writes (the cutover's D32); the owner decides
  with counsel whether it is acceptable (§3).
- D8: no rename of `foreign/idr/`. Reason: the one Modular port adapts
  into `foreign/idr/lib/Transforms/`, no whole vendored unit is
  planned, and a rename would touch CMake presets, PINS.md, bootstrap
  paths and every `#include` root for no change in meaning. A proposal
  that brings a whole vendored unit decides its directory then.
- D9: the sweep's scope is every tracked file less one listed exclusion
  set, each exclusion with its reason (§2; built in 0004). Reason: about
  900 scripts, build files, programs and documents of ours fell outside
  an inclusion list by kind without being listed.
- D10: the gate reads its facts from the data that holds them: a fork
  file's holder from the pin, the required texts from the identifiers in
  use, a port's attribution from its part (§2; built in 0004). Reason:
  each was a fixed answer that is wrong for a case the policy already
  admits.
- D11: a port's provenance is read from every comment block, and a
  named but unlicensed provenance blocks the port. Reason: Modular's
  `Bitcode/17/` files name their origin in prose alone ("The writer is
  taken from Julia's LLVM downgrader", `BitcodeWriter17.cpp:14-18`),
  with no license or copyright of that project.

**Open, for the owner** (besides §3's GMP question, with counsel):
whether a port's changes note ("Modified by Bjorn Pagen, 2026: <what
changed>", which Apache-2.0 §4(b) requires) names only what changed,
or also the source path and revision, as the policy's earlier text
did. Both readings are the owner's D1. Default: what changed only, a
dependency the port replaces included, with the path and revision held
once, in the port's PINS.md entry and the commit message. Reason:
writing them into the note holds the fact twice, beside PINS.md, and
makes a comment cite a document, which AGENTS.md says comments never
do. The one port landed writes the revision in its note ("from
Modular's 9211931"), so the default, if the owner keeps it, drops the
revision from that one note.
