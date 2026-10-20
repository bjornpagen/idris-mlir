<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0016: licensing: every file says whose it is

**Status:** built (3a275cf0, d06ed15c): `LICENSE`, `NOTICE`, `LICENSES/`
with `THIRD-PARTY.md`, the SPDX line on every file in scope, the line
`idris-mlir-tblgen` writes into every generated dialect module
(`writeLicense`), and the gate, `tools/licenses.sh`, run by
`tests/licenses` in `make check` (34/34 on arm64 macOS at c4d38e9b). The
code is the specification of all of it. What remains is three small
edits and one measurement, none on `make self`'s path and none owed
until a binary ships. Deleted when §1 is done; the rules of §2 move with
its second item. Not legal advice: GMP's terms need counsel, and their
one home is `LICENSES/THIRD-PARTY.md`'s GMP paragraph.

## 1. What remains

1. **The port's changes note.** Under §2's last rule, the note in
   `foreign/idr/lib/Transforms/Deduplicate/EliminateDuplicateFunctions.cpp`
   drops "from Modular's 9211931"; the source and revision stay in
   PINS.md `eliminate-duplicate-functions` and the porting commit.
   *Acceptance:* the note names what changed only, and `tests/licenses`
   passes. *Waits on:* nothing.
2. **The porting rules' home.** §2's rules move into `foreign/README.md`,
   which states only the basic protocol today, and this file is deleted
   in the same change. *Acceptance:* `foreign/README.md` states every
   rule of §2, and nothing else names them. *Waits on:* nothing.
3. **The gate reads its last fixed answers from the data.**
   - `tools/licenses.sh` recognises a port by `Apache-2.0` in its SPDX
     expression, and its part by the prose "port of <part>'s" in its
     PINS.md entry, so a port under another licence §2 admits is
     reported `wrong`. The PINS.md entry gains a field naming its part,
     as `sites:` names its files, and the gate reads the port set and
     the part from it.
   - `LICENSES/THIRD-PARTY.md`'s rows are a second copy of the pin set
     (`.gitmodules`, the bootstrap's toolchain). The gate reads the
     submodules and requires a row for each. The LLVM row also gains
     what reaches a shipped binary and it does not name: compiler-rt's
     builtins, which every program links (`--rtlib=compiler-rt`), and
     libc++, libc++abi and libunwind in our tools (same licence, no new
     text); "runtime bitcode joins programs" moves to no row, since the
     runtime is ours. The file's opening sentence, "Every program this
     compiler makes is statically linked", follows 0002's linking rule:
     static but for the system's C library.

   *Acceptance:* `tests/licenses` gains a witness for each (a port
   under another admitted licence passes; a submodule with no row
   fails) and passes on the tree. *Waits on:* nothing.
4. **Whether a program carries GMP when it uses no `Integer`.** `llvm-nm`
   on a program that uses no `Integer` (*conjecture*: it carries none,
   since an archive links only the members a reference pulls). The
   answer is written into `THIRD-PARTY.md`'s GMP paragraph, which then
   says which shipped programs the relink kit concerns. *Waits on:*
   nothing; arm64 macOS builds programs today.

## 2. Rules that govern until §1's second item moves them

- **A port** keeps its licence, its copyright and every header block,
  and gains an SPDX line and a changes note; vendored third parties stay
  unmodified submodules. Ours is 0BSD.
- **A file of several provenances** names them in one compound SPDX
  expression, and their texts join `LICENSES/`. Reason: Modular's tree
  has such files (its `Bitcode/` copies nest LLVM's line,
  `ConcurrentMPMCQueue.h` a BSD-2-Clause notice; *read* at `9211931`).
- **A rebuild is ours:** it names its design in comments without a path,
  and names path and revision in its commit message. Copied text makes
  a port, whatever the line count.
- **A port's provenance is read from every comment block,** and a named
  but unlicensed provenance blocks the port. Reason: Modular's
  `Bitcode/17/` files name Julia's LLVM downgrader in prose alone
  (`BitcodeWriter17.cpp:14-18`).
- **A port's changes note** ("Modified by Bjorn Pagen, 2026: <what
  changed>", Apache-2.0 §4(b)) names what changed only, a dependency the
  port replaces included (*decision*). Reason: the source path and
  revision are held once, in the PINS.md entry and the commit message; in
  the note they would be a second copy, and a comment that cites a
  revision cites a document, which comments never do.
