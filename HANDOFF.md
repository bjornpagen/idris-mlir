# Handoff (2026-10-09)

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
- **Done:**
  - the fork is in (compiler/idris, BSD-3), pruned and rewritten so the
    compiler can compile it: no `believe_me`, `%unsafe`, `%foreign` or
    existentials; concrete records; a function-based parser; the
    delayed-elaboration knot cut; base-backed primitives; the context table
    on `Linear.Array`;
  - the frontend runs on it with byte-identical output over the 702-program
    corpus;
  - the frontend reports every independent rejection in one run.
- **The first self-compile:** stage 0 (the frontend on Chez) compiling its
  own sources gave 44 rejections:
  - 37 "polymorphism";
  - 6 escape hatches, in our own frontend code (`believe_me` in
    Frontend/Driver.idr and Program.idr, `assert_smaller` in MLIR.idr and
    Profile.idr);
  - 1 dependent field (`CaseTree args` in Core.Context.Context).
- **Fix round 1 is in the working tree, uncommitted** (about 44 files). Our
  `IdrisMLIR.Term` moves from a nested datatype (`Term a` with `Under k a`)
  to `Term n` with `Fin n` variables: still well scoped, but monomorphic.
  The fork's traversals and Functor instances follow. Stage 0 builds with
  it.
- **Next:**
  1. re-run the self-compile and the 702-program corpus comparison
     (scratch scripts are not kept; the commands are `make fork frontend
     prefix libs host-libs PINS=true CHECKOUT_PREFIX=<p> HOST_PREFIX=<h>`,
     then the frontend's package mode to install compiler/idris into the
     prefix, then `idris-mlir-front -p idris-compiler -p mlir-linear` on
     compiler/src/IdrisMLIR/Frontend/Driver.idr);
  2. commit what holds;
  3. continue by cause, in this order, decided:
     - a "polymorphism" or "dependent field" whose differing arguments are
       only indices the representation does not depend on is fixed in the
       compiler (instances and field types keyed by representation:
       generalise the runST/phantom fix in
       Frontend/Translate/{Instances,Types,Recursion}.idr);
     - recursion through other implementations with a finite instance set
       is fixed in the compiler (the closure computed as a fixpoint, within
       the budgets);
     - only genuinely growing polymorphic recursion is refactored in code;
     - our own escape hatches are rewritten honestly.
- **Then:**
  - the stage chain (stage 1, 2 and 3 with the fixpoint stage 2 = stage 3 on
    both targets);
  - the test runner off Chez (orchestration in sh, generators compiled by
    idris-mlir, an `--exports` query instead of the stock REPL);
  - `tests/toolchain/static-linking` covering `idris-mlir-front`;
  - AGENTS.md's Chez exception narrowed to stage 0 and bench.

**Proposals** (`proposals/README.md`):
- 0001: Rust;
- 0002: what its qualification has not run;
- 0003: the bootstrap and the suites on both targets;
- 0004: a typed APL;
- 0005: shards;
- 0006: flattened data;
- 0007: the type checker.

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
