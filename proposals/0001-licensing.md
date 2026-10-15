# 0001: licensing: every file says whose it is

**Status:** decided by the owner 2026-10-14, built and pushed the
same day (3a275cf0): L1 to L4 are in the tree (LICENSES/, NOTICE,
the sweep, `tools/licenses.sh`, `tests/spec/licenses`). At 552d682a
`make check` was 27/27 with the licenses gate and the full suite green
(*measured* 2026-10-14, HANDOFF.md). At ccaba89c `make check` is 27/27
again, `spec/licenses` among them (*measured* on the typecheck machine
2026-10-14); the one failure at 3de67510, `spec/time-trace` finding the
culled profiler's name in a verbatim research note under `sources/`,
was fixed there by 0002 §3. x86_64 Linux has run nothing of this tree,
so the gate is NotRun there. No port has landed: the gate prints
"ports: none yet". What remains is L5 (§6: the dialect generator writes
its own SPDX line, so the generated modules lose their exclusion) and
L6 (§6: the sweep's scope is the whole tree less one listed exclusion
set, and the gate reads its three facts from the data that holds them);
both are to be built, and proved by `make check`, on the typecheck
machine, before 0004's swarm packet fixes its disjoint writes, since
they touch `foreign/idr/tools/idris-mlir-tblgen.cpp` and
`tests/spec/licenses`, which 0004's lanes L5 and L8 own. §5's GMP
question is the owner's with counsel and has its default taken; §4's
changes note is the owner's too, since it amends his D1, and has its
default taken (§9). §7's rename is decided against. This proposal is
deleted when L5 and L6 are built and
the owner accepts the built state; §5's default and question then live
in `LICENSES/THIRD-PARTY.md`'s GMP paragraph. The sections below are
the policy as built; §2 describes the tree *before* the sweep and is
kept as the record of what was found. Claims are marked: *read* (the
path), *measured*, *recalled*, *conjecture*, *decision*. This file is
the record of the policy. It is not legal advice, and the one item that
needs a lawyer's eye is named as such in §5.

**The one sentence.** Take the state of the art wherever it exists
(upstream MLIR first, Mojo where Mojo is structurally better, ported
outright when porting beats rewriting) and make that fearless by having
every file in the tree carry its provenance and license in one SPDX
line, so the 0BSD part (ours), the Apache-2.0-with-LLVM-exceptions part
(Mojo and MLIR-derived) and the BSD-3 part (the Idris fork) live
together with nothing ambiguous to audit later. The model is 9front's:
the new work is licensed permissively under our name, the inherited
parts keep their own licenses and their own copyrights, and the
boundary is written on every file, not remembered.

## 1. The policy (*decision*)

- **New code is ours, under the repository's license.** The root
  `LICENSE` text (ISC/0BSD family: "Permission to use, copy, modify,
  and/or distribute this software for any purpose with or without
  fee...") is the license of everything we write. It matched the SPDX
  `0BSD` template exactly (§6), so the identifier is `0BSD`.
- **Ported code keeps its license, its copyright and its name.**
  A file ported from Mojo or adapted from MLIR/LLVM keeps every
  upstream header block verbatim, gains an SPDX line, and gains a
  changes note ("Modified by Bjorn Pagen, 2026: ..." in one line), as
  Apache-2.0 §4(b) requires for modified files
  (`LICENSES/Apache-2.0.txt:98-99`, *read*). The LLVM exception waives
  §4(a), (b) and (d) only for portions embedded in object code
  (`LICENSES/LLVM-exception.txt:3-6`, *read*), so in source every
  condition holds. We never relicense upstream code, never strip a
  header, and never let a port lose its origin. The same for the Idris
  fork: Edwin Brady's copyright and the BSD-3-Clause text in
  `compiler/idris/LICENSE` stand; our changes there are the fork's,
  recorded as PINS.md records them.
- **The test is provenance, not line count.** Where we take code (a
  function, a pass skeleton, a table), it is a port under the rule
  above, however small. Where we take an algorithm or a structure and
  write every line ourselves, it is a *rebuild*: the file is ours
  (0BSD), its comments name the design the way comments here already
  name upstream ("upstream's inliner", "Mojo's ready set"), with no
  path or revision, since comments do not cite documents; the commit
  message names the source path and revision. A rebuild gets no PINS.md
  entry, because none of upstream's text is carried that could drift.
  An estimate written as "N of its lines carry over" describes a port,
  whatever the proposal calls it. The bench's C and Idris programs are
  rebuilds by this rule: each names the design it follows in its first
  comment ("Perceus's cfold.kk", "Lean's binarytrees.st.lean",
  `bench/c/cfold.c:1-3`, `binary-trees.c:1-2`, *read*).
- **Vendored third parties stay submodules** (`third_party/`, the
  toolchain pins): untouched, their licenses theirs, inventoried in
  §5 because static linking is distribution.
- **`sources/` keeps its own rules** (snapshots with provenance
  READMEs, such as `sources/code/modular/SNAPSHOT.md`) and is out of
  this proposal's sweep.

## 2. Where it stood before the sweep (*read*, 2026-10-14)

- Root `LICENSE`: our text, plus a paragraph carving out
  `compiler/idris/` under its BSD-3. No NOTICE file. No other
  license file in our parts of the tree.
- **Zero** SPDX identifiers and zero copyright headers in our
  source: `foreign/` 314 files, `compiler/src/` 55, `runtime/`
  73, `libs/` 5, `compiler/idris/` 202. Not one `SPDX-` line, not
  one `Copyright` line (grep). A clean slate: one mechanical pass
  could make the whole tree self-describing, and no header
  archaeology was needed.
- The fork (`compiler/idris/LICENSE`): BSD-3-Clause, Copyright
  (c) 2020 Edwin Brady. Per-file headers: none. Our changes to it
  are recorded in PINS.md and `upstream/<bug>/pull-request.diff`.
- Mojo (`~/Documents/modular`, re-read at `9211931`, the revision
  `sources/code/modular/SNAPSHOT.md` and 0004 §8 name; the earlier
  reading at 4b0d20f is superseded by this one, and every Modular line
  number below is 9211931's):
  - The repository `LICENSE` is Apache License v2.0 with LLVM
    Exceptions (`LICENSE:1-3`, the exceptions at `:207-221`), with
    LLVM's paragraph on third-party code (`:223-235`): such code is
    marked by its own LICENSE file or by terms at the top of every
    file. The snapshot's copy is byte-identical (`cmp`).
  - Every C++ and TableGen file under `Mojo/lib`, `Mojo/include`,
    `Support/`, `AsyncRT/` and `Cache/` carries Modular's prose header
    ("Copyright (c) 2026, Modular Inc. All rights reserved. Licensed
    under the Apache License v2.0 with LLVM Exceptions:
    https://llvm.org/LICENSE.txt",
    `Mojo/lib/Transforms/EliminateDuplicateFunctions.cpp:1-12`,
    `AutomaticInline.cpp:1-12`): 968 `.cpp`, `.h` and `.td` files,
    none without it, and with the 16 `.inc` and `.def` files beside
    them 984, none without it (find and grep). mojo §6 and 0004 §8
    count 981 across the same trees by a rule the report does not
    state; the difference changes nothing here.
  - Twelve of them carry an SPDX line, which the earlier reading
    missed: the eight copies of LLVM's bitcode writer under
    `Mojo/lib/Compiler/ObjectCompiler/LLVM/Bitcode/{19,21}/` keep
    LLVM's own header, SPDX line included, nested below Modular's
    (`BitcodeWriter21.cpp:1-20`); Support's three BumpAllocator files
    add one in a second Modular block (`Support/lib/BumpAllocator.cpp:13-19`);
    and `AsyncRT/include/AsyncRT/Support/ConcurrentMPMCQueue.h:14-16`
    nests Cameron Desrochers's BSD-2-Clause notice under "Adapted by
    Modular", its license spelled out (`BSD 2-Clause "Simplified"
    License`) rather than written as SPDX's identifier, `BSD-2-Clause`.
    A Modular file can therefore carry more than one provenance, which
    §3 and §4 provide for.
  - A provenance can also be prose alone: the four files under
    `Bitcode/17/` say "The writer is taken from Julia's LLVM downgrader"
    with no license or copyright of that project
    (`BitcodeWriter17.cpp:14-18`). None of them is a planned port; the
    porting protocol reads every comment block of a file for its origin
    for this reason (§4).
  - There is no NOTICE file at the root (`ls`). `Licenses/` is the MAX
    Community License for shipped products and a third-party notice for
    Modular's binaries (`Licenses/README.md:1-13`, `Licenses/LICENSE:1-7`);
    none of it travels with the source (mojo §6).
  - What Apache §4 requires of us: keep the license text, keep the
    copyright notices, mark modified files, keep any NOTICE (none).
    The patent grant travels with the code.
- MLIR/LLVM upstream (the pinned tree): Apache-2.0 WITH LLVM-exception,
  with an SPDX line per file and no per-file copyright line: the header
  says "Part of the LLVM Project, under the Apache License v2.0 with
  LLVM Exceptions" (`.toolchain/llvm-project/mlir/lib/Transforms/Utils/Inliner.cpp:1-7`,
  `mlir/lib/Dialect/Func/Transforms/DuplicateFunctionElimination.cpp:1-7`,
  *read*), and `llvm/LICENSE.TXT` names no copyright holder (grep). Our
  in-tree dialect takes that layout, and since the sweep an SPDX line on
  every file as LLVM's files have; its copyright line is ours (§3).
- Third-party pins in shipped binaries (static; distribution is the
  act that matters): musl (MIT, the Linux target's libc), snmalloc
  (MIT), ryu (Apache-2.0 OR BSL-1.0), fast_float (Apache-2.0 OR MIT OR
  BSL-1.0), simdutf (Apache-2.0 OR MIT), and **GMP, LGPL-3.0-or-later
  OR GPL-2.0-or-later** (`third_party/gmp/README:1-18`; texts in
  `COPYING.LESSERv3`, `COPYINGv2`, `COPYINGv3`). The earlier reading
  wrote GMP as GPL-3.0/LGPL-3.0; GMP's own README is the terms. AGENTS.md's
  static-linking rule makes the LGPL's relink and notice obligations a
  real question for shipped binaries; §5 takes it. Chez Scheme and
  Idris 2 (host side only) keep theirs.

## 3. The identifiers

One line per file, first line where the language allows, in the
comment syntax of the file:

| Part | SPDX line | Attribution |
| --- | --- | --- |
| Ours | `SPDX-License-Identifier: 0BSD` | `Copyright (c) 2026 Bjorn Pagen` |
| Mojo port | `SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception`, or the compound expression when the file nests another license | Modular's header block verbatim, every nested block kept, plus our changes line |
| MLIR/LLVM port | `SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception` (upstream's own line, kept) | LLVM's header verbatim ("Part of the LLVM Project"), which has no copyright line, plus our changes line |
| Idris fork | `SPDX-License-Identifier: BSD-3-Clause` | `Copyright (c) 2020 Edwin Brady` on upstream's files; a new file we add to the fork is ours under BSD-3-Clause, `Copyright (c) 2026 Bjorn Pagen` |

Decisions taken here:

- The root text is `0BSD` (§6 resolved the ISC-or-0BSD conditional
  by template match).
- A file that is ours but sits in the fork is BSD-3-Clause: one
  license per tree is worth more than claiming the permissive part
  inside it, and it keeps any future re-sync trivial. Two of the 202
  fork files are ours, not upstream's (*read*): `Libraries/Data/Table.idr`,
  written for the fork (f21bcbfe), and `IdrisPaths.idr`, which stands
  for the module upstream's Makefile generates
  (`third_party/Idris2/Makefile:79-80`); neither path is in the pin's
  `src/` (a comparison of the two file lists). Both carry Edwin Brady's
  line today, because `tools/licenses.sh --apply` writes upstream's
  holder on every fork file (`tools/licenses.sh:80`). *Decision:* which
  holder a fork file names is read from the pin: a file whose path is
  in `third_party/Idris2/src/` is upstream's, any other is ours. The two
  files are corrected and the script and gate derive the holder in L6.
  Reason: whose a file is was a fact the script did not hold, so it
  wrote one answer for both; the pin holds it.
- A file with more than one provenance names all of them: the SPDX
  line is the compound expression in SPDX's list identifiers (for
  example `Apache-2.0 WITH LLVM-exception AND BSD-2-Clause` for
  `ConcurrentMPMCQueue.h`, whose own line spells the license out), with
  every upstream line kept verbatim beneath it, and every license text
  it names is in `LICENSES/` in the same change. Reason: §2 found such
  files in Modular's tree, one of them with a line no SPDX tool reads.
  *Decision:* which texts `LICENSES/` must hold is derived from the
  identifiers in use, not listed: today the script and the gate each
  keep a fixed list of four (`tools/licenses.sh:83-85`, under a comment
  that says "every identifier in use", `:82`; `tests/spec/licenses/run:27`),
  which a compound port would leave short. L6.
- Committed generated files carry the line their generator writes. The
  generated dialect modules (`compiler/src/IdrisMLIR/Syntax/` and
  `Dialect/`, twelve files, committed and checked by
  `tests/spec/dialects-current`) are ours, generated from our ODS by our
  generator, so `idris-mlir-tblgen` writes the `0BSD` line and the
  copyright line at the top of its output, before the module's doc
  comment (`foreign/idr/tools/idris-mlir-tblgen.cpp:1783, 1837`), and
  the exclusion in `tools/licenses.sh:17-20, 30` goes (L5). Reason: one
  rule for every committed file, and an exclusion list is a branch the
  generator can delete. Build-tree generated files are out of scope.
- **The scope is the tree, less one listed exclusion set** (*decision*).
  As built, the sweep's scope is a list of included kinds: C++ in
  `foreign/` and `runtime/`, Idris in `compiler/src/`, `libs/` and the
  top of `tests/`, and `tools/*.sh` (`tools/licenses.sh:13-15, 28-33`).
  Every other kind is skipped without being listed, against the
  script's own rule ("Out of scope, listed not skipped silently",
  `:15`). Outside `third_party/` and `sources/`, 3,115 tracked files
  carry no SPDX line (*measured*, `git grep -L` at ccaba89c). Most are
  fixtures and expected outputs, rightly without one. The rest are
  code and prose of ours that a header changes nothing in: 751 test
  `run` scripts (26 of them in `tests/spec/`), 25 other shell scripts
  (17 in `tests/lib/`), 12 `CMakeLists.txt`, the Makefile, five
  `.ipkg` files, the bench's 25 C and 27 Idris programs, and 59
  Markdown files (proposals, AGENTS.md, PINS.md, the upstream
  reports), while `foreign/README.md` already carries the line as a
  Markdown comment. So the scope becomes every file `git ls-files`
  lists, less one exclusion set `tools/licenses.sh` holds with a reason
  for each: the other parties' trees (`third_party/`, `sources/`);
  bytes a test or a record compares or quotes (fixture sources whose
  line numbers reach expected output, every `expected` and input file,
  `bench/runs/`, `bench/profiles/`, the reproducers under `upstream/`);
  files with no comment syntax (JSON, TSV, SVG, `.patch` and `.diff`,
  the license texts themselves); and the generated modules until L5. A
  test's `run` script is in scope wherever it sits, since no expected
  output reads its lines. The line is written in each kind's comment syntax (`#` for
  shell, CMake and Make; `--` for Idris and `.ipkg`; `//` for C, C++
  and TableGen; `<!-- -->` for Markdown). Reason: an inclusion list by
  kind is a second copy of "what is ours" that already drifted from the
  tree; with exclusions as the data, a new kind is in scope by default
  and the gate names it. L6.
- Tests and `.mlir` fixtures are ours unless a fixture is a ported
  test, which follows the port rule. Fixtures stay out of the sweep
  (listed in `tools/licenses.sh:15-17`), because a header changes their
  line numbers and so their expected output.
- **The gate checks a port's attribution by its part** (*decision*).
  `tests/spec/licenses` refuses an Apache-2.0 file without a `Copyright`
  line (`tests/spec/licenses/run:23`). That is Modular's form; LLVM's
  header has no copyright line (§2), so an MLIR port that follows the
  table above would be refused. The check becomes the table's: Modular's
  copyright line for a Modular port, LLVM's "Part of the LLVM Project"
  line for an MLIR/LLVM port, the part named by the port's PINS.md
  entry. No MLIR port is planned (0004 §7 sends MLIR changes upstream),
  so nothing is refused today; the gate is corrected in L6 because a
  rule that refuses a conforming file is wrong before its first case.

## 4. The porting protocol (Mojo, MLIR, anyone)

1. Copy the file or function with every header block intact into its
   home (`foreign/idr/` in upstream layout for C++; Idris-side ports
   keep upstream module structure where one exists). Read every comment
   block of the file for its origin, not only its license lines: a
   provenance can be prose alone (§2's `Bitcode/17/` files), and a
   provenance the file names but does not license is resolved before
   the port lands, or the port does not land.
2. Add the SPDX line above the header and a one-line changes note,
   "Modified by Bjorn Pagen, 2026: <what changed>", as §1 gives it and
   as Apache-2.0 §4(b) requires (a notice that the file was changed).
   A dependency the port replaces is what changed, so the note names
   it: the first planned port, `EliminateDuplicateFunctions.cpp`,
   includes AsyncRT and Mojo's CallGraphUtils (`:14-15, 18`), neither of
   which comes (0004 §8). The source path and the revision it was taken
   at (`9211931` for every Modular file read so far) live once, in the
   PINS.md entry of step 3 and in the commit message. *Default taken*
   for the owner's question in §9: the earlier text also wrote path and
   revision into the note, which held the fact twice (beside PINS.md)
   and made a comment cite a document, which AGENTS.md says comments
   never do; no port has landed, so nothing in the tree changes either
   way.
3. Record the port in PINS.md like every other deliberate
   deviation: what, from where, at what revision, what changed.
   A port is a pin: when upstream moves, the port is re-read
   against it, never silently drifted from. `tests/spec/licenses`
   refuses an Apache-2.0 file that PINS.md does not name
   (`tests/spec/licenses/run:24`).
4. The `LICENSES/` directory (REUSE convention) holds the full
   texts: `0BSD.txt`, `Apache-2.0.txt`, `LLVM-exception.txt`,
   `BSD-3-Clause.txt`, and any other a port names. The root
   `LICENSE` stays the human entry point and names the parts; the root
   `NOTICE` carries the Apache attribution notices in one place.

What is ported from Modular, at what size and against which LLVM
(Modular builds at LLVM `8d4fc8f1` with its own patches,
`bazel/public-patches/llvm_source.bzl:7, 12-54`, *read*), is 0004
§8's: one port (EliminateDuplicateFunctions, 301 lines, `wc`) and five
rebuilds. 0004's lane L6 lands the port under this protocol, with
`tests/spec/licenses` as its proof (0004 §10).

## 5. The inventory and the GMP question

`LICENSES/THIRD-PARTY.md` names every pin and submodule that
reaches a shipped binary, its license, and what the binary therefore
carries; it is kept by the same change that adds or moves a pin.
0013's crate graph, when it is unparked, enters it by the same rule.
GMP is its one non-permissive entry.

**What reaches a binary** (*read*). The runtime calls GMP for
`Integer`: 29 distinct `mpz_` functions and macros (and the types
`mpz_ptr`, `mpz_srcptr`), all in seven of `runtime/Big/`'s eight files,
plus `mp_set_memory_functions`, which routes GMP's allocation through
ours (`runtime/Alloc/Gmp.cpp:35`); 30 entry points in all (grep). The
bigs' own interface is `runtime/Big/Big.h`, and `runtime/Big/` is 526
lines (`wc`). GMP enters every link as a static archive on the link
line, never as bitcode: `-lgmp` from the musl sysroot on Linux, the
sysroot's `libgmp.a` on macOS (`CMakeLists.txt:175, 219`); what joins a
program's module as bitcode is our runtime, not GMP. Our tools link the
runtime too, because folders call it, and the runtime's interface links
GMP (`runtime/CMakeLists.txt:223-224`; `foreign/idr/CMakeLists.txt:113`),
so a shipped compiler carries GMP as well as every program it makes.
Whether a program that never uses `Integer` carries any GMP code is
*conjecture*: an archive links only the members a reference pulls, and
the driver internalizes the runtime and runs O3 before the link, so
none is expected. `llvm-nm` on such a program's executable settles it
at the first build after 0004's cutover; the kit below is owed only by
a binary that contains GMP. The repository distributes source only:
`tools/bootstrap.sh` and `make` build every binary on the user's
machine, so nothing is owed by us until a binary ships.

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
object per codegen bin in bin-name order (0004 D32, which names this
kit; `-c` is `foreign/idr/lib/Driver/Options.cpp:24-29`), the prepared
runtime object (`--print-runtime`), the link line's remaining arguments
with GMP among them (`--print-link-flags`, `Options.cpp:105-113`), and
GMP's source at the pin. For a compiler release: the static libraries
and the final link command its build already writes (*conjecture*: no
new code, since CMake links the tools from those archives). In both,
the notice and the two license texts travel beside the binary. Reasons:
the link already has this shape (separate objects, GMP an archive, the
link line printable), so the default costs no code; replacing GMP costs
a bignum implementation and, *conjecture*, asymptotic speed: `pidigits`
at 10,000 digits runs at 0.66x of its C, both over GMP (clang 0.445 s
against ours 0.669 s, `bench/runs/2026-10-13-9a1b7b1-darwin-arm64/results.md:31`,
`bench/c/pidigits.c:3`, *measured*), and a schoolbook replacement would
widen that gap; and no binary ships today. Every user who ships a
program this compiler made inherits the same obligations, which the
kit is what makes possible.

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

## 6. Stages

**Built (3a275cf0, 2026-10-14).** L1 to L4 landed in one change:
`LICENSES/` (0BSD, Apache-2.0, LLVM-exception, BSD-3-Clause texts and
`THIRD-PARTY.md`), root `NOTICE` and `LICENSE`, the SPDX sweep over
every in-scope file by `tools/licenses.sh` (one script for ours and
the fork's, which holds the scope and the listed exclusions), and the
gate at `tests/spec/licenses`. The gate was proven both ways when
built: deleting one header made it fail, restoring it made `make check`
pass (*measured*). The root text matched the SPDX `0BSD` template
exactly (ISC minus the attribution-reproduction sentence), so §3's
conditional resolved to `0BSD`. Today the in-scope trees carry the
line throughout: `foreign/` 317 files, `runtime/` 73, `compiler/src/`
43 (the generated modules excluded), `libs/` 5, `compiler/idris/` 202,
`tools/` 13 (grep, ccaba89c; the same at 3de67510).

**Remaining: L5.** `idris-mlir-tblgen` writes the SPDX and copyright
lines in the generated dialect modules' header; `tools/dialects.sh
generate typecheck` regenerates the twelve modules with the typecheck
build's generator (`tools/dialects.sh:15-19`); `tools/licenses.sh`
drops their exclusion. Proof: `tests/spec/licenses` and
`tests/spec/dialects-current` green in `make check`.

**Remaining: L6.** `tools/licenses.sh` takes its scope from `git
ls-files` less its listed exclusions (§3), writes the line in each
kind's comment syntax on every file of ours outside them (§3 counts
them: the scripts, build files, bench programs and Markdown), reads a
fork file's
holder from the pin and corrects `Table.idr` and `IdrisPaths.idr`, and
derives the required license texts from the identifiers in use; the
gate does the same and checks a port's attribution by its part. In the
same change `LICENSES/THIRD-PARTY.md`'s GMP paragraph (`:22-27`), which
today names the question for the owner and counsel but not the default,
states §5's default (LGPL-3.0 §4(d)(0) by a relink kit, the program
half being the archive `-c` writes, 0004 D32) and the open question,
since it becomes their home when this file is deleted. Proof:
`tests/spec/licenses` green, and proven both ways again (a new file
kind without a line fails it; a compound identifier without its text
fails it). L5 and L6 change no build output, so the typecheck machine
proves them with `make check`.

**Ports.** None has landed. The opt-in SCC pipeline of 552d682a was
our own code under upstream's inliner, not a Mojo port, and 0004's
cutover deletes it (0004 §3.3, §6). 0004 §8 ranks what the cutover
ports and rebuilds, and its lane L6 lands the one port under §4.

## 7. The layout the licenses live in

License is per file (the SPDX line), never per directory. A port lives
where the code belongs structurally, with its provenance on its face.
Directories answer "what system is this", headers answer "whose is it".
The layout (*read*, 2026-10-14):

| Directory | What it is | License part |
| --- | --- | --- |
| `LICENSES/`, `LICENSE`, `NOTICE` | every text, the inventory, the attribution | none of its own |
| `foreign/idr/` | the `idr` dialect and driver (C++), in upstream MLIR's in-tree layout | ours; ports inside it keep their headers |
| `compiler/src/` | the frontend (Idris) | ours |
| `compiler/idris/` | the fork of Idris's compiler | BSD-3-Clause, one license per tree |
| `runtime/`, `libs/` | the runtime; the Idris packages we ship | ours |
| `tests/`, `bench/`, `tools/` | tests, benchmarks, build and driver scripts | ours (fixtures and records excluded from headers, listed in `tools/licenses.sh`) |
| `third_party/` | unmodified submodule pins | theirs, untouched |
| `upstream/` | bug reports and patches against pinned upstreams | ours; the patch targets keep theirs |
| `sources/` | the research library (papers, snapshots, notes) | each item's own, provenance in place |
| `proposals/` | designs, in work order | ours |

Made with this proposal: `LICENSES/` and `NOTICE` exist, and
`foreign/README.md` states what `foreign/` means: code laid out as its
upstream lays it out, where ports land with provenance.

**The rename of `foreign/idr/` is not taken** (*decision*). It was
deferred until a whole vendored unit made the distinction load-bearing.
None is planned: the one Modular port (EliminateDuplicateFunctions,
301 lines) adapts into `foreign/idr/lib/Transforms/`, AsyncRT never
comes (0004 §8), and 0013's parked `foreign/rust/bind/` is our own code
in cargo's layout, which `foreign/README.md`'s definition already
covers. A rename would touch CMake presets, PINS.md, bootstrap paths
and every `#include` root for no change in meaning. A proposal that
brings a whole vendored unit decides its directory then.

## 8. What this is not

Not a relicensing of anything upstream, not a CLA, not a promise about
GMP, not a gate on reading upstream code (reading was never the
problem), and not busywork headers for their own sake. The point is
that taking the state of the art (Mojo's scheduler, MLIR's drivers,
anyone's better structure) becomes a mechanical, auditable act instead
of a provenance question nobody can answer in a year.

## 9. Decisions (the record)

- D1 (owner, 2026-10-14): the policy of §1, the identifiers of §3, the
  protocol of §4, the inventory of §5. Built.
- D2: the root text is `0BSD`, by template match. Built.
- D3: one license per tree for the fork; new fork files are ours under
  BSD-3-Clause, and which fork files are new is read from the pin (L6).
- D4: a port keeps every header block; a file with several provenances
  names them in one compound expression of SPDX list identifiers, and
  their texts join `LICENSES/`. Reason: Modular's tree has such files
  (§2).
- D5: a rebuild is ours, names its design in comments without a path,
  and names path and revision in its commit message; copied text makes
  a port, whatever the line count.
- D6: committed generated files carry their generator's line; the
  generated-module exclusion goes (L5).
- D7: GMP's default is LGPL-3.0 §4(d)(0) by a relink kit, whose program
  half is the archive `-c` writes (0004 D32); the owner decides with
  counsel whether it is acceptable (§5).
- D8: no rename of `foreign/idr/` (§7).
- D9: the sweep's scope is every tracked file less one listed exclusion
  set, each exclusion with its reason (§3, L6). Reason: about 900
  scripts, build files, programs and documents of ours fell
  outside an inclusion list by kind without being listed.
- D10: the gate reads its facts from the data that holds them: a fork
  file's holder from the pin, the required texts from the identifiers
  in use, a port's attribution from its part (§3, L6). Reason: each was
  a fixed answer that is wrong for a case the policy already admits.
- D11: a port's provenance is read from every comment block, and a
  named but unlicensed provenance blocks the port (§4). Reason: §2's
  `Bitcode/17/` files.
- D12: L5 and L6 land before 0004's swarm packet fixes its disjoint
  writes (status). Reason: they touch `idris-mlir-tblgen.cpp` and
  `tests/spec/licenses`, which the packet gives to 0004's L5 and L8.

**Open, for the owner** (besides §5's GMP question, with counsel):
whether a port's changes note names only what changed, as §1 words it,
or also the source path and revision, as §4's earlier text did. Both
are the owner's D1. Default: what changed only, the path and revision
held once in PINS.md and the commit message (§4 step 2); 0004 §8's
licensing steps follow the default.
