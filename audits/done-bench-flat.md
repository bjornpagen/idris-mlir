<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane bench-flat: bench/ as one flat directory

## The layout now

`bench/<name>/` holds `Main.idr`, `main.c`, `input` or `input-from`, and
`packages` where the program uses libs/. Nothing else. `bench/records/`
holds what was measured: the run record
`2026-10-13-9a1b7b1-darwin-arm64/` and the four dated measurements of the
compiler (`2026-10-14-f0-stage0.md`, `2026-10-15-self-s1.md`,
`2026-10-16-self-emit.md`, `2026-10-17-self-growth.md`). `tools/profile.sh`
writes its uncommitted traces there too. `bench/run.sh`, `bench/report.sh`
and `bench/README.md` are the only other files.

## Moved and renamed

- `bench/c/<name>.c` moved to `bench/<name>/main.c`, every one of them.
  `bench/c/` is gone.
- Renamed to the game's names: `bench/mandelbrot-pbm` became
  `bench/mandelbrot` (the game's bitmap program), `bench/nbody` became
  `bench/n-body`, and our counting program `bench/mandelbrot` became
  `bench/mandelbrot-count`. Their C went along
  (`c/mandelbrot-pbm.c`, `c/nbody.c`, `c/mandelbrot.c`).
- `bench/runs/2026-10-13-9a1b7b1-darwin-arm64/` moved to
  `bench/records/`, and `bench/profiles/2026-*.md` moved to
  `bench/records/`.

## Deleted (one line of reason each)

- `bench/fannkuch-linear/build`, `bench/qsort/build`,
  `bench/fannkuch-redux/build`, `bench/k-nucleotide/build`: build
  litter.
- `bench/profiles/2026-10-13T181352Z-43a9e235a9be-dirty-every-interfaces-export.time-trace.json`:
  a gitignored trace, which is untracked litter. HANDOFF.md no longer says it is in the tree.
- `bench/profiles/README.md`: what it said about traces (the zones, the
  zero cost when tracing is off, why the runtime has no zones, traces not
  committed) is now in `tools/profile.sh`'s header, the tool's one home.
  `bench/profiles/` is gone.
- `bench/{fasta,fasta-redux,mandelbrot-pbm,reverse-complement}/compare`:
  a per-benchmark comparison mode. It is replaced by the one rule in
  `agree` (below), which needs no mark.
- `bench/pidigits/libs` (`-lgmp`): a second statement of GMP.
  `idris-mlir --print-link-flags` already names GMP on both targets
  (`IDRIS_MLIR_GMP`). pidigits' C builds and prints the recorded output
  without it.
- `bench/fannkuch-linear/reference` and `bench/spectral-norm-linear/reference`:
  each is replaced by `main.c`, a symlink to the C of the program it ports
  (`../fannkuch-redux/main.c`, `../spectral-norm/main.c`). The C has one
  copy and the layout has no special case.
- The README's results section, per-program notes and caveats. They restated
  the record and gave "*recalled*" timings with no kept record. What each
  program computes is already in its `Main.idr` header. The game's C-entry
  provenance (which gcc entry, by whom, which entries are threaded) moved
  into each game program's `main.c` header. The stale "chameneos-redux,
  thread-ring and meteor-contest are not here" paragraph is gone, because other
  lanes are adding those programs.

## Rewritten

- **bench/run.sh**
  - It reads `bench/<name>/main.c`, and builds a generator from
    `bench/<gen>/main.c`.
  - A benchmark without `main.c` is refused, where before it was silently
    left without a clang column.
  - **One comparison rule, `agree`.** It replaces the two modes
    `compare=bytes` and "numbers only".
    - Outputs equal byte for byte agree.
    - Otherwise both must be text (no NUL byte) with the same last byte.
      They must also be the same token for token: text between numbers byte
      for byte, an integer's digits exactly, and only a number written with
      a point or an exponent held to 1e-9.
    - This is stronger than the old "numbers only" mode, which ignored all
      text and let a 10-digit pidigits group be off by up to 3 under the
      relative tolerance. A binary output (the PBM) still agrees only byte
      for byte.
    - Checked by hand on cases: float digits agree; an integer's last digit,
      whitespace, line structure, a missing final newline and a binary byte
      all differ.
    - Checked on the tree: every `main.c` prints, on its smoke input,
      exactly the bytes in `tests/bench/smoke/<name>.out`. The exceptions are
      harmonic and n-body, which differ only in `%.17g` against shortest
      round-trip digits and agree under the rule.
  - **A build failure now fails the run.** Before, a benchmark this
    compiler failed to build was reported on stderr, but the run still
    printed "Outputs agree" and kept the record with an n/a column. That is
    a check that could not fail. Now the run goes on to measure the rest,
    prints the table, names the unbuilt benchmarks, exits 1 and keeps no
    record. The Chez column is still timed only.
  - The overloaded `reference` variable (first a benchmark name, then an
    output file) is gone, along with the `compared` list and its
    self-comparison of this compiler's output with itself.
- **bench/README.md**: rewritten as five paragraphs: the layout, how a run
  builds, compares and reports, the three kinds of program, the records,
  and how to read a run.
- **bench/\*/main.c headers**: the game provenance was added. n-body's
  comment no longer names `bench/nbody/Main.idr`. regex-redux's comment is
  merged.
- **References fixed across the tree**:
  - `README.md`: the record links, and the sentence on what bench/ holds.
  - `HANDOFF.md`.
  - `tools/self.sh` (a comment).
  - `tools/profile.sh`: the output directory and the header.
  - `tools/licenses.sh`: the exclusion is now `bench/records/*`. The
    `*/compare */reference */libs` marks were dropped because no benchmark
    has them now.
  - `.gitignore`: `bench/records/*.time-trace.json`.
  - `tests/bench/records/run`: it now iterates over the run-record
    directories in `bench/records/`.
  - `tests/bench/smoke`: `mandelbrot{,-pbm}`, `nbody` `.in`/`.out` were
    renamed to `mandelbrot-count`, `mandelbrot` and `n-body`, and so were
    their `expected` lines.
  - `bench/records/2026-10-14-f0-stage0.md` (its two path mentions).
  - Live proposals: 0003, 0006, 0008, 0009, 0011, 0013, 0014, 0016, 0017,
    and proposals/README.md. `bench/c/` became `main.c`, and
    `bench/runs`/`bench/profiles` became `bench/records`. 0006's "holds F0
    alone" was corrected.
  - `proposals/0004-representation/{dispatch,parts,findings}` and
    `audits/` were left as written: they are dated records of past lanes,
    naming the tree as it then was.

## Verification

- `bench/run.sh --runs 1 fib harmonic mandelbrot-count` and
  `bench/run.sh --runs 1 tak` passed: outputs agree, and harmonic agrees
  through the float rule. Each ran one compile at a time.
- `bench/run.sh --runs 1 reverse-complement` passed: the input-from
  generator is read from `bench/fasta/main.c`, and the output is binary-safe
  text.
- `bench/run.sh --runs 1 fannkuch-linear` showed the symlinked C builds
  and runs (30.1 s). Under the old script it then "agreed" with this
  compiler refused, which is the defect fixed above.
- `bench/run.sh --runs 1 --record DIR qsort` now exits 1, names qsort, and
  leaves DIR uncreated.
- `tests/bench/records` and `tests/bench/report` pass. They were run
  directly against their `expected`, because `make test` could not build
  the runner at the time: another lane was editing `tests/Main.idr` (an
  error at line 261).
- `tests/bench/smoke` (run directly) gives the same per-benchmark verdicts
  as the audit, under the new names. It is not in this lane's scope, and
  its NEEDS-ACCEPTANCE line is repo-tests'.
- In `make check`, the only failure from bench/ is
  `bench/chameneos-redux/compare` in spec/licenses (see below).
  spec/dialect-text and spec/file-size fail on other lanes' files.

## Left for others

- **`bench/chameneos-redux/compare`** (`bytes`) was written by the
  chameneos lane in the old layout. `run.sh` no longer reads a `compare`
  file, because its output agrees byte for byte under `agree` anyway.
  Delete it. It is also what fails spec/licenses now that `*/compare` is
  no longer excluded.
- **`tests/bench/smoke`** (repo-tests): it walks every `bench/*/Main.idr`.
  - It says "no recorded input" for chameneos-redux and meteor-contest
    (and will for thread-ring and regex-dna) until their `.in`/`.out`
    exist, or until it becomes `smoke@<name>` from the bench listing.
  - That generator should take each benchmark's smoke input and its
    expected output from data. The game's own small-input outputs, made by
    `main.c` (they equal the Idris outputs today under `agree`), would
    remove the hand-kept `.out` copies.
- **proposals/0017** plans a harness as `bench/dmp/`, which would break
  the flat layout. It belongs elsewhere (tools/ or its own directory)
  when it is built.

## Compiler bugs seen (not fixed; this lane changes no compiler code)

- **reverse-complement is 76x slower than the kept record.** This compiler
  took 42.45 s on `fasta 25000000`, against 0.555 s in the 2026-10-13
  record. clang took 1.74 s and Chez 27.0 s. The output still agrees. This
  is a performance regression that no test catches, a candidate for
  SUMMARY §5.
- **fannkuch-linear and qsort are refused.**
  `unsupported (polymorphism): Builtin.DPair.(#)` /
  `Linear.Notation.MkBang: a shape whose rank no analysis fixes: [__]`.
  This is SUMMARY §5 item 2 and repo-tests item 2.
- The smoke verdicts match the audit's §5 entries:
  - leaks: binary-trees, deriv, fannkuch-redux, fasta, fasta-redux,
    mandelbrot, pidigits and reverse-complement exit 0 with live cells;
  - refusals: k-nucleotide, spectral-norm-linear and unionfind;
  - nqueens: an `llvm.call` operand type mismatch;
  - regex-redux: idr-rc-exclusive;
  - spectral-norm: times out after 60 s.
