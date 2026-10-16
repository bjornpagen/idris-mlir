<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0016: licensing: every file says whose it is

**Status:** built. What remains is the owner's acceptance, his two
questions (§3, §4) and four small edits (§2), all **AFTER-SELF**:
nothing on `make self`'s path reads a licence, and nothing is owed until
a binary ships (the repository ships source). Deleted when the owner
accepts and §2 is done. Not legal advice; §3 needs counsel.

## 1. Built (the code is the specification)

- L1 to L4, D1, D2 (3a275cf0): `LICENSE` (0BSD), `NOTICE`, `LICENSES/`
  (the texts, and `THIRD-PARTY.md`, the inventory of what reaches a
  shipped binary), the SPDX line on every file in scope, the porting
  protocol in `foreign/README.md`.
- L5, D6 (d06ed15c): `idris-mlir-tblgen` writes the line into every
  committed dialect module (`writeLicense`,
  `foreign/idr/tools/idris-mlir-tblgen.cpp:1785`), so none is excluded.
- L6, D3, D9, D10 (d06ed15c): `tools/licenses.sh`, gated by
  `tests/spec/licenses` in `make check`: the scope is every tracked file
  less one reasoned exclusion list (`:37-56`), a fork file's holder is
  read from the pin (`:92-96`, `:153`), the required texts from the
  identifiers in use (`:222-226`), a port's attribution from its PINS.md
  part (`:228-256`). *Measured* 2026-10-15 on the live tree: exit 0, one
  port, texts `0BSD Apache-2.0 BSD-3-Clause LLVM-exception`.
- The one port: Modular's `EliminateDuplicateFunctions.cpp` at `9211931`,
  as `foreign/idr/lib/Transforms/Deduplicate/EliminateDuplicateFunctions.cpp`,
  its header kept; PINS.md `eliminate-duplicate-functions`.
- D8: no rename of `foreign/idr/`; a whole vendored unit gets its own
  directory beside it, named for its origin (`foreign/README.md`).

## 2. What remains (all AFTER-SELF)

1. **Acceptance:** rides the owner's build, `make check` on both targets
   (33/33 on the arm64 typecheck machine at d06ed15c; x86_64 Linux
   NotRun). No work of its own.
2. **The note's revision:** under §4's default, the port's changes note
   drops "from Modular's 9211931" (`EliminateDuplicateFunctions.cpp:14`).
3. **The protocol's home:** D4, D5 and D11 (§4) move into
   `foreign/README.md`, which states only the basic protocol; until then
   this file is their one home, and it cannot be deleted before.
4. **The gate's last fixed answers** (D10's rule, unfinished):
   `tools/licenses.sh` names a port by `Apache-2.0` in its expression
   (`:170`) and its part by the prose "port of <part>'s" in its PINS.md
   entry (`:247`), so a port under another licence D4 admits is reported
   `wrong`. The entry gains a field naming its part, as `sites:` names
   its files, and the gate reads the port set and the part from it.
   Likewise `THIRD-PARTY.md`'s rows are a second copy of the pin set
   (`.gitmodules`, the bootstrap's toolchain): the gate reads the
   submodules and requires a row for each. Its LLVM row names neither
   compiler-rt's builtins, which every program links (`--rtlib`,
   `tools/bootstrap.sh:848,872`), nor libc++, libc++abi and libunwind in
   the tools, and "runtime bitcode joins programs" is our runtime's, not
   LLVM's (same licence: no new text).

## 3. GMP (the owner's, with counsel)

The terms, the default (D7: GMP stays, statically linked, and a shipped
binary meets LGPL-3.0 §4(d)(0) with a relink kit, the program half the
archive `idris-mlir -c` writes) and the question (is the kit acceptable
for a compiler release, programs, and programs users ship, or must GMP
go) have one home, `LICENSES/THIRD-PARTY.md`'s GMP paragraph, which
outlives this file. The runtime's GMP surface is 29 `mpz_` functions and
macros in seven of `runtime/Big/`'s eight files, plus
`mp_set_memory_functions` (`runtime/Alloc/Gmp.cpp:25`) (*read*, grep).
Owed at the owner's first build: `llvm-nm` on a program that uses no
`Integer`, to settle whether it carries GMP (*conjecture*: no, an
archive links only the members a reference pulls). If GMP goes, a
permissive bignum replaces it behind `runtime/Big/Big.h`, chosen in its
own proposal by `pidigits`' ratio to its C (0.66x today over GMP,
*measured*, `bench/runs/2026-10-13-9a1b7b1-darwin-arm64/results.md:31`).

## 4. Decisions that still govern

- D1 (owner, 2026-10-14): ours is 0BSD; a port keeps its licence, its
  copyright and every header block, and gains an SPDX line and a changes
  note; vendored third parties stay unmodified submodules.
- D4: a file of several provenances names them in one compound SPDX
  expression, and their texts join `LICENSES/`. Reason: Modular's tree
  has such files (its `Bitcode/` copies nest LLVM's line,
  `ConcurrentMPMCQueue.h` a BSD-2-Clause notice; *read* at `9211931`).
- D5: a rebuild is ours, names its design in comments without a path,
  and names path and revision in its commit message; copied text makes
  a port, whatever the line count.
- D11: a port's provenance is read from every comment block, and a named
  but unlicensed provenance blocks the port. Reason: Modular's
  `Bitcode/17/` files name Julia's LLVM downgrader in prose alone
  (`BitcodeWriter17.cpp:14-18`).

**Open, for the owner** (amends D1): whether a port's changes note
("Modified by Bjorn Pagen, 2026: <what changed>", Apache-2.0 §4(b))
names only what changed, or also the source path and revision. Default:
what changed only, a dependency the port replaces included; the path
and revision are held once, in the PINS.md entry and the commit message.
Reason: in the note they are a second copy, and a comment that cites a
revision cites a document, which AGENTS.md says comments never do.
