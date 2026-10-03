# R1: what every lane shares

Status: R0 is merged (main at 0641826). R1 has not started: its first
wave (ownership, lower, specialize-eval, stack-inline-expect-canonicalize-fold)
was cut off before any commit and thrown away. Run it again from current main;
then wave 2 (dialect-hooks, passes, tools, runtime) from the merged wave 1.
Lanes share a 4-CPU machine: one build directory each.

Every R1 brief (the other files beside this one) starts from main after R0
(three commits on 4f08662: b0b2fa7 the libraries and the shared modules, c5ff298 rt.platform,
0641826 the rules and the ratchets). Read AGENTS.md, then foreign/idr/lib/MODULES.md: both are
binding, and MODULES.md is the how-to (shape, libraries, converting an area,
pitfalls). Converted examples: `lib/Facts` (idr.facts, with glue and a
hook), `lib/Graph` (a template kept thin), `lib/Layout` (a class split into
units), `lib/Support` (actions with an out-of-line TypeID), `lib/Target`
(glue moved to the library whose logic it runs), `runtime/Platform`
(rt.platform, units grouped by system).

## What R0 left

- Modules, each its own library (`idr_library`,
  foreign/idr/cmake/IdrLibrary.cmake), `LINKS` = exactly its imports
  (checked by tests/spec/module-links; the build refuses a module outside a
  library's link closure, tests/toolchain/module-imports):

  | Module | Library | Imports |
  |---|---|---|
  | idr.mlir | idr_mlir | |
  | idr.dialect | idr_ods | |
  | idr.support | idr_support | idr.mlir |
  | idr.ranges | idr_ranges | idr.mlir |
  | idr.graph | idr_graph | idr.mlir, idr.dialect |
  | idr.layout | idr_layout | idr.mlir, idr.dialect |
  | idr.facts | idr_facts | idr.mlir, idr.dialect |
  | idr.target | idr_target | idr.mlir |
  | rt.platform | (file set of idris_rt) | |

- `idr_dialect` is the aggregate the tools link: Registration.cc, the
  dialect's hooks and every area not yet converted, as plain units, linking
  every module library PUBLIC. Your new library goes into its link list.
- idr.dialect already re-exports the dialect's whole interface (every op,
  type, attribute, interface, enum, pass constructor and option struct, and
  the helpers of idr/Idr.h). idr.mlir exports what lib/ used so far; you
  will add names.

## Shared files

Several lanes edit these; keep your edits to the lines described, so that
merges stay mechanical:

- `foreign/idr/lib/Mlir.cppm`: add `using` lines (and global module
  fragment includes) only, each in its sorted place; never reorder or
  remove. `foreign/idr/lib/Dialect/Dialect.cppm`: as R0 left it, you
  should not need to touch it; if you do, add lines only.
- `foreign/idr/CMakeLists.txt`: add your directory to the `foreach(area`
  list if it is new, and your library to `idr_dialect`'s link list. Nothing
  else.
- `tests/spec/no-local-headers/allowed`, `tests/spec/file-size/allowed`:
  delete your own lines (the briefs list them); both tests fail on a line
  that is no longer needed, and on any new finding.
- `PINS.md`: only entries whose sites you move.

## Setup

- Your worktree: make `.toolchain` a real directory with hard-link copies
  (`cp -al`) of `llvm-musl` and `sysroot` from
  /home/user/idris-mlir/.toolchain and symlinks for the rest (a symlinked
  `.toolchain` crashes clang-scan-deps with "Sysroots differ"). Get the
  submodules with `git clone --shared` from the main checkout at their
  pinned commits. `make build` builds the per-checkout Idris prefix.
- Iterate in a scratch build: `.toolchain/cmake/bin/cmake --preset dev -B
  <scratch>/build`, `ninja -C <scratch>/build -j3 idr_dialect`.

## Gates

- Pure refactor: run
  `findings/module-reorg/dumps.sh
  <worktree> <scratch>/dumps-before` after your first `make build`, before
  any change, and again into `<scratch>/dumps-after` at the end; the two
  `.sha256` files must be identical except `runtime-all-symbols.txt`
  (private names may change; `runtime-symbols.txt`, the exported ones, may
  not).
- `make check`, `make build`, `make test`, `make test-idr`,
  `make test-mlir-tools`, all with `time_scale=3`.
- Lint (`--preset lint`, MODULES.md): no new finding in your files. The
  findings that move with code from before the modules may stay.
- Commits: one per logical change, tests in the same commit, each ending
  with the two trailer lines of the R0 brief. Never push.
