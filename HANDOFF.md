# Handoff (2026-10-12)

Two independent agents, each started locally in Claude Code in a clone of
bjornpagen/idris-mlir at `main`. Paste the prompt under each heading as
the agent's first message. They touch disjoint things: the first works
in a separate clone of llvm-project and only updates `upstream/` status
here; the second owns this repository's toolchain and code.

State, updated 2026-10-12.

**The cutover.** Proposal 0002 is committed, and it builds:
`foreign/idr` is an in-tree MLIR dialect in upstream's layout (headers
and .cpp, no C++ module), functions are `idr.func` with their facts as
inherent attributes, analyses run under the analysis manager, the round
is upstream's composite pass, the runtime is headers and .cpp, the
frontend emits no erased value, and compile-time evaluation (`idr-eval`,
its JIT and its child) is gone. Its first real build (4d5e7e8f, arm64
macOS) passed, and a Prelude program compiled by it runs with no live
cells at exit. The suites ran once, before the fixes that followed:
`make test` 84 of 415, `make test-idr` 251 of 272, `make
test-mlir-tools` 15 of 16. The failure clusters those runs showed are
fixed in the commits after it (isolate's linear closures, the
quantities check's keys, rc's reuse of atoms, the newtype's field
quantity, block naming, the parsers' inherent facts), and the gate has
not run again since. `make typecheck`, which compiles every unit with
the dev warnings as errors without stage 2, and `make check` pass. Its
qualification is the 0002 README's "Qualification".

**Toolchain.** Built on arm64 macOS, pin llvm main 7208ba24, one recipe
(`tools/bootstrap.sh`, into `.toolchain/llvm`). Before the cutover, on
2026-10-10, `make build` passed, `make check` was 26/26, `test-idr`
269/269 and `test-mlir-tools` 17/17, and two `make test` programs,
`programs/prelude/every-interfaces-export` and `every-types-export`,
compiled and then hit their time limits. A stage-2 rebuild takes about 3
minutes with ccache. x86_64 Linux is still unbuilt at this pin (0001's
gate G1).

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
- **`make self` (1ce907d3)** builds stages 1 to 3 and checks that stage 2
  matches stage 3: the same executable, module and Core. The new tests'
  end-to-end runs and FileCheck with the native frontend are after that,
  and the same on x86_64 Linux has not been run.
- **Then:** the test runner off Chez (orchestration in sh, generators
  compiled by idris-mlir, an `--exports` query instead of the stock
  REPL); `tests/toolchain/static-linking` covering `idris-mlir-front`;
  AGENTS.md's Chez exception narrowed to stage 0 and bench; every
  rejection message made precise (named in the user's request of
  2026-10-10: what was found, where, why, and what form compiles);
  emission's memory (9.1 GB for a 405 MB text module: the print-write
  patch in the scratch audit, and R7's bytecode rule, now measurable).
- The rewrites self-hosting forced, and the compiler features that would
  replace the regressions among them, are proposal 0010.

**Proposals** (`proposals/README.md`), in their numbered order, which
is the order the work is done:
- 0001: self-hosting (its stage S, §6.1), behind its gate G1 (its §12):
  what remained of the Linux bootstrap and of the representation cutover;
- 0002: the cutover that executes 0001's stages C and H, committed;
  qualifying it is 0001 §6.1's first steps;
- 0003's stage 1: the purge of today's array stack and its MLIR-first
  rebuild, as one cutover, right after `make self`;
- 0004 and 0005: sharding (0004's P1, P2 and P4; 0005's S0, S1, S2 and
  S8);
- then the array work: 0003's typed array language, with 0006's array
  interpreter (static normalization on the type checker's evaluator),
  0007's tables and 0008's flattened data as its consumers, and 0009's
  type checker on 0006's machine;
- 0010: the compiler features self-hosting asked for, once `make self`
  is green;
- parked: 0011 (the relational core), 0012 (Rust), 0005's S3 to S6 and
  S9 to S10, and 0004's P3.

The research behind 0009, 0003 and 0008 is in `sources/`, with reading
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

Its two phases landed: the trunk cutover (20fcfadb, 1677b8cb) and the
representation cutover (93f5d9c9, 327c2e30, 0451b1b8). What it left open
is now the repository's own: the bootstrap and the suites on both
targets at the pin, and the rest of the representation cutover's
qualification, both in 0001's gate G1
(`proposals/0001-get-back-on-track.md` §12).
