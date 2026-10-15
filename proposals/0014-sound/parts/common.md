<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
## Common obligations (every lane)

- **The packet is the contract.** `proposals/0014-sound/README.md` (the
  architecture: §2 rules, §3 findings, §4 selected representations, §5
  library table) and `ownership.json` decide; this dispatch quotes what you
  need. AGENTS.md binds as always. Where live source contradicts the packet,
  report the exact evidence to the coordinator and keep working on the rest;
  do not redesign.
- **Write only your exclusive files.** Re-read a file immediately before
  editing it; other lanes are writing nearby files at the same time. Never
  revert, reformat or "fix" a change you did not make. A hub file
  (`CMakeLists.txt`, `*.ipkg`, `Makefile`, `PINS.md`, `upstream/README.md`)
  is the coordinator's: put the exact text you need in your handoff.
- **Two hosts, forever.** Idris you write (frontend, fork, `libs/`, test
  machinery) must build with the stock Idris on Chez and with idris-mlir
  (`make self`): stay inside the subset idris-mlir compiles (nothing it
  refuses: no escape hatch, no `%foreign`, no megamorphic recursion; see
  `tests/reject/` for the rules). Use linear (quantity 1) types where they
  help; they mean the same on both hosts.
- **Every number needs authority**: a published default, a measurement, or a
  stated derivation in a comment that says why; otherwise it is debt and the
  comment says so. No retry counts, no deadlines standing in for a missing
  fact; never delete an existing protective cap.
- **Verification policy (this machine).** Build and run anything but the
  LLVM project itself, which is not built here: never `make bootstrap`,
  `tools/bootstrap.sh`, `make build`, `make test*`, `make self` or
  `make compile` (each needs the built LLVM). Shared build state is the
  coordinator's while lanes run, so never run the whole `make typecheck`,
  `make fork`, `make frontend`, `make libs`, `make host-libs`, `make runner`,
  `make check` or `make typecheck-dialects` (they write the shared prefixes,
  the runner, or the generated `compiler/src/IdrisMLIR/{Dialect,Syntax}`,
  from every lane's sources at once). Allowed, and expected wherever it
  applies to your files:
  - C++ units: `python3 tools/check-units.py <files>` (syntax-only with the
    typecheck build's exact commands; writes nothing).
  - ODS: regenerate the headers your units need, one lane at a time:
    `. tools/host.sh && with_lock build/.typecheck.mutex cmake --build --preset typecheck --target <IdrOpsIncGen|IdrRuntimeAbiIncGen|idris-mlir-tblgen|...>`.
    The generated Idris modules are the coordinator's: put the ODS change in
    your handoff.
  - Idris: a private copy under `/tmp/0014-<lane>/`, checked or built there by
    the pinned `.toolchain/idris2/bin/idris2` with
    `IDRIS2_PREFIX=.toolchain/idris2` and `IDRIS2_PACKAGE_PATH` naming
    `build/idris2-host/idris2-0.8.0` (the fork, as `make typecheck` installed
    it). Code that runs on the stock host (a generator, a property, a model)
    is also run there, on Chez: that is real evidence, report it.
  - C and C++ that link no LLVM library (the runtime under `runtime/`, a
    `prop.h` program, a model): compiled by the host's `clang`/`clang++` into
    `/tmp/0014-<lane>/` and run.
  - A spec: `IDRIS_MLIR_ROOT=$PWD sh tests/spec/<name>/run` diffed against its
    `expected`. A spec's exit code is not its verdict: diff.
  Behaviour of idris-mlir and idris-mlir-opt is the owner's build after
  integration; every new or changed test this machine cannot run carries a
  first-line `NEEDS-ACCEPTANCE:` mark saying what to confirm.
- **Tests.** A brittle test is deleted, never restated (packet §2). A new test
  states its contract on the shared machinery (packet §4.5, §4.7, §4.8) and
  nothing more.
- **No commits, no pushes, no git writes.** The coordinator integrates.
- **Handoff** (your final message, compact): changed paths, each mapped to an
  obligation; for each obligation, its representation line (the guideline's
  last bullet: the state made unrepresentable, the check moved to a boundary,
  the branch deleted, or why the case is essential); contracts supplied; consumer adaptations made; hub text the
  coordinator must apply; checks actually run with their results, or NotRun;
  unresolved seams, each with its evidence.
