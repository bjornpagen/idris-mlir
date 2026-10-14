# 0001: licensing: every file says whose it is

**Status:** decided by the owner 2026-10-14 and built the same day:
L1 to L4 are in the tree (LICENSES/, NOTICE, the sweep, the fork
script, `tests/spec/licenses` — check is 27/27 with it). What
remains is only §5's GMP question, which is the owner's with
counsel, and §7's deferred rename. This proposal is deleted when
the owner accepts the built state. Claims are marked: *read* (the
path), *measured*, *decision*.
This file is the record of the policy; it is not legal advice, and
the one item that needs a lawyer's eye is named as such in §5.

**The one sentence.** Take state of the art wherever it exists --
upstream MLIR first, Mojo where Mojo is structurally better, ported
outright when porting beats rewriting -- and make that fearless by
having every file in the tree carry its provenance and license in
one SPDX line, so the 0BSD part (ours), the Apache-2.0-with-LLVM-
exceptions part (Mojo and MLIR-derived) and the BSD-3 part (the
Idris fork) live together with nothing ambiguous to audit later.
The model is 9front's: the new work is licensed permissively under
our name, the inherited parts keep their own licenses and their own
copyrights, and the boundary is written on every file, not remembered.

## 1. The policy (*decision*)

- **New code is ours, under the repository's license.** The root
  `LICENSE` text (ISC/0BSD family: "Permission to use, copy, modify,
  and/or distribute this software for any purpose with or without
  fee...") is the license of everything we write. §3 pins its exact
  SPDX identifier by template match; the owner calls this part
  "the 0BSD part" and the identifier follows the text, not the name.
- **Ported code keeps its license, its copyright and its name.**
  A file ported from Mojo or adapted from MLIR/LLVM keeps the
  upstream copyright line and license header verbatim, gains an
  SPDX line, and gains a changes note ("Modified by Bjorn Pagen,
  2026: ..." in one line) as Apache-2.0 §4(b) requires for modified
  files. We never relicense upstream code, never strip a header,
  and never let a port lose its origin. The same for the Idris
  fork: Edwin Brady's copyright and the BSD-3-Clause text in
  `compiler/idris/LICENSE` stand; our changes there are the fork's,
  recorded as PINS.md already records them.
- **Borrowing is by value, stated.** Where we take an algorithm or
  structure but write the code, the file is ours (0BSD part) and
  the comment cites the source as comments already do ("upstream's
  X", a path). Where we take code -- a function, a pass skeleton, a
  table -- it is a port under the rule above, however small. The
  test is provenance, not line count.
- **Vendored third parties stay submodules** (`third_party/`, the
  toolchain pins): untouched, their licenses theirs, inventoried in
  §5 because static linking is distribution.
- **`sources/` keeps its own rules** (snapshots with provenance
  READMEs, already in force) and is out of this proposal's sweep.

## 2. Where it stands (*read*, 2026-10-14)

- Root `LICENSE`: our text, plus a paragraph carving out
  `compiler/idris/` under its BSD-3. No NOTICE file. No other
  license file in our parts of the tree.
- **Zero** SPDX identifiers and zero copyright headers in our
  source: `foreign/` 314 files, `compiler/src/` 55, `runtime/`
  73, `libs/` 5, `compiler/idris/` 202 -- not one `SPDX-` line,
  not one `Copyright` line (grep, §2's audit). A clean slate: one
  mechanical pass can make the whole tree self-describing, and no
  header archaeology is needed.
- The fork (`compiler/idris/LICENSE`): BSD-3-Clause, Copyright
  (c) 2020 Edwin Brady. Per-file headers: none. Our changes to it
  are recorded in PINS.md and `upstream/<bug>/pull-request.diff`.
- Mojo (`~/Documents/modular`, read at 4b0d20f): the repository
  `LICENSE` is Apache License v2.0 with LLVM Exceptions; files
  carry the prose header ("Copyright (c) 2026, Modular Inc. ...
  Licensed under the Apache License v2.0 with LLVM Exceptions:
  https://llvm.org/LICENSE.txt"), no SPDX line, and there is no
  NOTICE file at the repository root. The LLVM exception is the
  standard one (no copyleft trigger from linking/obligations on
  output); Apache §4 requires of us: keep the license text, keep
  copyright notices, mark modified files, keep any NOTICE (none).
  Its patent grant travels with the code.
- MLIR/LLVM upstream (the pinned tree): Apache-2.0 WITH
  LLVM-exception *with* SPDX lines per file -- the form our
  in-tree dialect already imitates in layout and now imitates in
  headers too.
- Third-party pins linked into every program (static; distribution
  is the act that matters): musl (MIT), snmalloc (MIT), ryu
  (Apache-2.0/BSL-1.0), fast_float (Apache-2.0/MIT/BSL-1.0),
  simdutf (Apache-2.0/MIT) -- and **GMP, dual GPL-3.0/LGPL-3.0**
  (`third_party/gmp/COPYING`, `COPYING.LESSERv3`). AGENTS.md's
  static-linking rule makes the LGPL's relink/notice obligations a
  real question for shipped binaries; it is inventoried in §5 as
  the one item needing a decision with counsel, not silently
  carried. Chez Scheme and Idris 2 (host side only) keep theirs.

## 3. The identifiers

One line per file, first line where the language allows, in the
comment syntax of the file:

| Part | SPDX line | Copyright line |
| --- | --- | --- |
| Ours | `SPDX-License-Identifier: 0BSD` | `Copyright (c) 2026 Bjorn Pagen` |
| Mojo port / MLIR-derived | `SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception` | upstream's, verbatim, plus our changes line |
| Idris fork | `SPDX-License-Identifier: BSD-3-Clause` | `Copyright (c) 2020 Edwin Brady` (existing files); new fork files ours under BSD-3-Clause so the fork stays one license |

Decisions taken here:

- The root text is matched against the SPDX templates in the same
  change; if it matches `ISC` rather than `0BSD` verbatim, the
  identifier is ISC and the root file is renamed in the inventory
  -- the text does not change, only its name is made exact.
- A file that is ours but sits in the fork is BSD-3-Clause: one
  license per tree is worth more than claiming the permissive
  part inside it, and it keeps any future re-sync trivial.
- Generated files (TableGen output, dialect builders generated
  from ODS) carry the identifier of their generator's output
  header if they are committed at all; build-tree generated files
  are out of scope.
- Tests and `.mlir` fixtures are ours unless a fixture is a ported
  test, which follows the port rule.

## 4. The porting protocol (Mojo, MLIR, anyone)

1. Copy the file or function with its header intact into its home
   (`foreign/idr/` in upstream layout for C++; Idris-side ports
   keep upstream module structure where one exists).
2. Add the SPDX line above the header and a one-line changes note
   with the source path and revision it was taken at (Mojo ports
   name the modular commit, as 0004's sources already do).
3. Record the port in PINS.md like every other deliberate
   deviation: what, from where, at what revision, what changed.
   A port is a pin: when upstream moves, the port is re-read
   against it, never silently drifted from.
4. The `LICENSES/` directory (REUSE convention) holds the full
   texts: `0BSD.txt` (or `ISC.txt` per §3), `Apache-2.0.txt`,
   `LLVM-exception.txt`, `BSD-3-Clause.txt`. The root `LICENSE`
   stays the human entry point and names the parts; a root
   `NOTICE` carries the Apache attribution notices in one place.

## 5. The inventory and the one open question

The same change writes `LICENSES/THIRD-PARTY.md`: every pin and
submodule that reaches a shipped binary, its license, and what
the binary therefore carries. GMP is its one non-permissive entry.
**Open, for the owner with counsel:** static PIE distribution
against LGPL-3.0 (relinkability and notice in a static binary).
Nothing in this proposal changes that situation; it makes it
visible in one place instead of implicit. If the answer is "not
acceptable", the follow-up is an arithmetic-library decision
(a permissive bignum, or GMP under terms counsel approves) as its
own proposal -- not a reason to delay identifiers.

## 6. Stages

| Stage | Work | Proof |
| --- | --- | --- |
| L1 | `LICENSES/` texts, root `NOTICE`, the root `LICENSE` naming the three parts with the exact identifier (§3), `LICENSES/THIRD-PARTY.md` | identifiers resolve against the SPDX list; texts byte-equal to the canonical ones |
| L2 | The sweep: SPDX + copyright line on every source file of ours (`foreign/`, `compiler/src/`, `runtime/`, `libs/`, `tools/`, `tests/` fixtures excluded where a header would change expected output -- those are listed, not silently skipped) | a spec test (below) enumerates the tree and finds none missing |
| L3 | The fork: SPDX lines on `compiler/idris/` files, by a script kept in `tools/` so a re-sync reapplies it; the diff to the pin stays header-only | re-running the script on a pristine pin reproduces the tree byte-for-byte outside recorded fork changes |
| L4 | The gate: `tests/spec/licenses` -- every in-scope file names an identifier from the allowed set, every ported file (listed in PINS.md) carries upstream copyright + changes line, `LICENSES/` holds each used text | `make check` green; deleting a header anywhere fails it (shown once in the stage's record) |

Then porting is open for business: the first port is expected to
be Mojo's inliner shape in 0004's F3, under §4, and its stage
record names the revision taken.

## 7. The layout the licenses live in

License is per file (the SPDX line), never per directory — a port
lives where the code belongs structurally, with its provenance on
its face. Directories answer "what system is this", headers answer
"whose is it". The current layout already mostly does that; the
audit (*read*, 2026-10-14) and the two changes this proposal makes
to it:

| Directory | What it is | License part |
| --- | --- | --- |
| `LICENSES/`, `LICENSE`, `NOTICE` | the obvious place: every text, the inventory, the attribution | — |
| `foreign/idr/` | the `idr` dialect and driver (C++), in upstream MLIR's in-tree layout | ours; ports inside it keep Apache headers |
| `compiler/src/` | the frontend (Idris) | ours |
| `compiler/idris/` | the fork of Idris's compiler | BSD-3-Clause, one license per tree |
| `runtime/`, `libs/` | the runtime; the Idris packages we ship | ours |
| `tests/`, `bench/`, `tools/` | tests, benchmarks, build/driver scripts | ours (fixtures excluded from headers, listed in `tools/licenses.sh`) |
| `third_party/` | unmodified submodule pins | theirs, untouched |
| `upstream/` | bug reports and patches against pinned upstreams | ours; the patch targets keep theirs |
| `sources/` | the research library (papers, snapshots, notes) | each item's own, provenance in place |
| `proposals/` | designs, in work order | ours |

Changes made with this proposal: `LICENSES/` and `NOTICE` exist;
`foreign/README.md` (new in L2's commit) states what `foreign/`
means — code laid out as its upstream lays it out, where ports
land with provenance — so the name stops being folklore.

Deferred to its own approved change, deliberately not bundled
here: renaming `foreign/idr/` (to `mlir/` or `dialect/`) so
`foreign/` could mean only vendored ports. It touches CMake
presets, PINS.md, bootstrap paths and every `#include` root for a
naming gain; it is worth doing exactly once, when the first
whole-unit Mojo port (0004 F3's scheduler is the candidate) makes
the distinction load-bearing, and not before.

## 8. What this is not

Not a relicensing of anything upstream, not a CLA, not a promise
about GMP, not a gate on reading upstream code (reading was never
the problem), and not busywork headers for their own sake: the
point is that taking the state of the art -- Mojo's scheduler,
MLIR's drivers, anyone's better structure -- becomes a mechanical,
auditable act instead of a provenance question nobody can answer
in a year.
