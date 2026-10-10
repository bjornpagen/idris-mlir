# Handoff (2026-10-10)

Two independent agents, each started locally in Claude Code in a clone of
bjornpagen/idris-mlir at `main`. Paste the prompt under each heading as
the agent's first message. They touch disjoint things: the first works
in a separate clone of llvm-project and only updates `upstream/` status
here; the second owns this repository's toolchain and code.

State, updated 2026-10-09 (evening).

**Toolchain.** The LLVM pin is llvm main 7208ba24, and the toolchain is one
recipe for both targets (`tools/bootstrap.sh`, into `.toolchain/llvm`).
No toolchain has been built with the patches the tree carries, so
`make build` refuses until `make bootstrap` runs. None of the C++ written
since then has been compiled. That covers:
- the configuration sweep;
- IORef as the array of rank 0, with the move-out read;
- Integer shifts;
- the string iterator;
- the growable `Array`;
- record boxing;
- the removal of global state;
- the typed `idr` dialect and its generator;
- the driver inversion (`idris-mlir` drives, `idris-mlir-front` is a
  file-to-file program);
- the `idr-identity` pass.

The generated `Dialect`/`Syntax` modules were written by hand to the
generator's format; the first `make build` regenerates them, must
reproduce them, and refreshes their fingerprints.

**Self-hosting.**
- **Stage 0 compiles itself (2026-10-10).** The frontend, built by the
  stock Idris and running on Chez, compiles its own sources
  (`IdrisMLIR/Frontend/Driver.idr` with `-p idris-compiler -p
  mlir-linear`) with no rejection and no error: a 405 MB MLIR module of
  58,305 functions and 7,664 data types, and its 74 MB Core, in 137 s at
  9.1 GB peak (arm64 macOS; phases: checks 0.4 s, reachable 4.2 s,
  translate 81 s, print 40 s, write 0.9 s). The fork installs in about
  75 s. The 702-program corpus's outputs are byte-identical before and
  after each change but one, by design (a type parameter named only in
  erased fields keys no data instance: `Equal`'s).
- **How to run it:** `make fork frontend prefix libs host-libs PINS=true
  CHECKOUT_PREFIX=<p> HOST_PREFIX=<h>`, then the frontend's package mode
  installs `compiler/idris` into `<p>` (`idris-mlir-front --prefix <p>
  --install idris-compiler.ipkg` from a copy of it), then
  `idris-mlir-front --prefix <p> -p idris-compiler -p mlir-linear
  --timing <t> --core <c> -o <m> IdrisMLIR/Frontend/Driver.idr` from a
  copy of `compiler/src`. Cap the Chez process's memory when running it by
  hand: a translator bug shows as unbounded growth, not as an error.
- **Not run:** the emitted module has not been parsed, verified or lowered:
  that needs the C++ toolchain built with the patches the tree carries
  (`make bootstrap`), which is not built here. So stage 1 (a native,
  static `idris-mlir-front`), stage 2 and stage 3 (the fixpoint, stage 2 =
  stage 3 on both targets) are next, and the new tests'
  end-to-end runs and FileCheck with them.
- **Then:** the test runner off Chez (orchestration in sh, generators
  compiled by idris-mlir, an `--exports` query instead of the stock
  REPL); `tests/toolchain/static-linking` covering `idris-mlir-front`;
  AGENTS.md's Chez exception narrowed to stage 0 and bench; every
  rejection message made precise (named in the user's request of
  2026-10-10: what was found, where, why, and what form compiles);
  emission's memory (9.1 GB for a 405 MB text module: the print-write
  patch in the scratch audit, and R7's bytecode rule, now measurable).
- The rewrites self-hosting forced, and the compiler features that would
  replace the regressions among them, are proposal 0009.

**Proposals** (`proposals/README.md`):
- 0001: Rust;
- 0002: what its qualification has not run;
- 0003: the bootstrap and the suites on both targets;
- 0004: a typed APL;
- 0005: shards;
- 0006: flattened data;
- 0007: the type checker;
- 0008: OpenTelemetry;
- 0009: the compiler features self-hosting asked for;
- 0010: a data-oriented, array-first frontend;
- 0011: the relational core, shared by the compiler and bumbledb;
- 0012: a sharded whole-program compiler, after 0004 and 0005;
- 0013: static normalization on the type checker's interpreter; no compile-time evaluation feature (decided, not built).

The research behind 0004, 0006 and 0007 is in `sources/`, with reading
notes in `sources/notes/`. Contiguous runs (one run cell for strings,
arrays and buffers) has no proposal yet. The LLVM submissions are in
`upstream/`; their status table says which is next.

## Agent 1: upstreaming

```
Read upstream/README.md in this repository, all of it, and do what it
says. You are the sending agent it describes. Start with the first row
of its status table marked "send next". Its rules are absolute: I (Bjorn)
approve every post one command at a time, everything ends with
"Assisted-by: Claude Code", you push only to my fork, one submission at
a time, trunk only, the diff applying to current llvm main and
clang-format clean, check-mlir left to LLVM's pre-merge CI. Before
anything else, confirm `gh auth status` and git's user.name/user.email,
and tell me what you found. Do not touch this repository's toolchain or
code; the only files you change here are upstream/README.md's status
table, upstream/NN-*/README.md's "Upstreaming plan" and PINS.md entries,
as its "After a pull request lands" and step 9 say, committed and pushed
to main.
```

## Agent 2: done

Its two phases landed: the trunk cutover (20fcfadb, 1677b8cb) and proposal
0002 (93f5d9c9, 327c2e30, 0451b1b8). What it left open is now the
repository's own: the bootstrap and the suites on both targets at the pin
(`proposals/0003-llvm-trunk.md`), and the rest of 0002's qualification
(`proposals/0002-representation-cutover/README.md`).
