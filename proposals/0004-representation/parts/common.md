<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
## Common obligations (every lane)

- **The packet is the contract.** `proposals/0004-representation/README.md`
  (§1 invariants, §2 rules, §3 findings, §4 shared contracts, §7 bugs, §9
  decisions) and `ownership.json` decide; this dispatch quotes what you
  need. AGENTS.md binds as always. Where live source contradicts the packet,
  report the exact evidence to the coordinator and keep working on the rest;
  do not redesign.
- **Write only your exclusive files.** Re-read a file immediately before
  editing it; other lanes are writing nearby files at the same time. Never
  revert, reformat or "fix" a change you did not make. A hub file (any
  `CMakeLists.txt`, `*.ipkg`, `Makefile`, `tools/**`, `PINS.md`,
  `upstream/**`, `tests/spec/**`, `tests/ACCEPTANCE.md`) and the generated
  `compiler/src/IdrisMLIR/{Dialect,Syntax,Encoding}/**` are the
  coordinator's: put the exact text you need in your handoff.
- **Hard cutover, zero backwards compatibility (the owner's rule).** The new
  representation replaces the old one in the same change, everywhere in your
  writes: no shim, alias, re-export, deprecated name, wrapper keeping an old
  signature, dual code path, fallback to the old form, compatibility flag,
  "legacy" branch, or comment promising a later removal. Old textual IR,
  bytecode, option names and layouts are not kept readable; fixtures you own
  are rewritten to the new form. A consumer outside your writes is named in
  your handoff for its owner to cut over, never served by a bridge you keep.
- **Map onto MLIR's grain (the owner's rule, 2026-10-17: "don't be afraid to
  churn massive portions of the codebase to be representation first to map
  well onto mlir").** Read the skill's section "Map onto MLIR's grain"
  before your first C++ or ODS edit. One op per semantics: never an optional
  operand, unit attribute or enum that switches an op's meaning, effects or
  valid states. A shared shape is an interface. Effects, constraints, result
  types, assembly formats, properties, folders and simple rewrites are
  declared in ODS. Values and memory live at different levels, lowered
  progressively. Cached analyses go through the `AnalysisManager`, dataflow
  through `DataFlowSolver`, lowering through `TypeConverter` and the
  conversion framework, symbols through `SymbolTable`, diagnostics through
  `emitError`, driver failures through `llvm::Error`, unreachable code
  through `ub`. Prefer deleting our C++ an upstream mechanism replaces to
  adding any; a new C++ abstraction says in its comment why no upstream
  mechanism fits.
- **Program with the types (Idris 2, after Brady; the owner's rule).** Read
  `.claude/skills/representation-first/SKILL.md`, the section "Program with
  the types: Idris 2, not Haskell", before your first Idris edit: index the
  invariant; decide with evidence, never a `Bool`; keep proofs and indices at
  quantity 0; return the value with what was learned; one record, never
  parallel lists; `List1` where empty would be an error; views and `with`.
  `List` is for sequential consumption only (the owner, 2026-10-17): a
  position is a `Vect n`/`Fin n` or, where it is hot and mutated, base's
  `Data.IOArray`; a key is a `SortedMap`; repeated appends are a
  `SnocList`; data that belong together are one record, never lists matched
  by position. No blanket rewrite: change a `List` where it is indexed,
  keyed, appended to in a loop or paired by position, in code your findings
  touch. `libs/mlir-array`'s linear arrays are runtime `%extern`s, so code
  the stock host runs (the frontend, `libs/`, the test machinery) never uses
  them. The C++ has its analogue: a `std::variant` or an enum where flags would
  combine, a type that carries a checked fact instead of a re-check, no
  sentinel and no null where a case is meant.
- **Two hosts, forever.** Idris you write (frontend, `libs/`, test machinery)
  must build with the stock Idris on Chez and with idris-mlir: stay inside
  the subset idris-mlir compiles (no escape hatch, no `%foreign`, no
  megamorphic recursion; `tests/reject/` shows the rules).
- **Every number needs authority**: a published default, a measurement, or a
  stated derivation in a comment; otherwise it is debt and the comment says
  so. Never delete an existing protective cap.
- **Verification policy (this machine).** No LLVM is built here: never
  `make bootstrap`, `tools/bootstrap.sh`, `make build`, `make test*`,
  `make self` or `make compile`. Shared build state is the coordinator's
  while lanes run, so never run `make typecheck` (or any `typecheck-*`
  part), `make check`, `make fork`, `make frontend`, `make libs`,
  `make runner`, or `tools/dialects.sh generate`.
  - **C++ lanes** do not compile during the swarm: the generated headers
    every unit includes come from every lane's ODS at once. Your evidence is
    the source: each selected representation built, each named predecessor
    gone (a `grep` for every deleted name finds nothing in your files), each
    consumer of yours adapted. The coordinator's `make typecheck` after
    integration is the gate, and its errors in your files come back to you
    as a repair dispatch.
  - **Idris lanes** work in a private copy, never the live tree:
    `mkdir -p /tmp/0004-<lane> && git -C /Users/bjorn/Documents/idris-mlir archive HEAD compiler tests libs | tar -x -C /tmp/0004-<lane>/`
    (HEAD is this packet's base at dispatch), then apply your own edits
    there as you make them in the tree. Build the frontend with the pinned
    Idris on Chez as `/tmp/0003c-gate/front.sh` does (read it), against the
    fork `make typecheck` installed (`build/idris2-host`), and run it over
    `tests/programs`, `tests/accept` and `tests/reject` with
    `/tmp/0003c-gate/scripts/runtest.sh` (read it) into
    `/tmp/0004-<lane>/out`, comparing status, stdout, stderr and Core with
    the base frontend built the same way in `/tmp/0004-<lane>/base`. Code
    that reads a generated module this wave changes (S0) is written against
    §4's names and built only at integration; say which in your handoff.
  - **The runtime lane** builds with the host clang and runs the runtime's
    property programs as `tests/toolchain` and 0002 §11 describe.
  - Every new or changed test this machine cannot run carries a first-line
    `NEEDS-ACCEPTANCE:` mark saying what to confirm.
- **Tests.** A brittle test is deleted, never restated. A test states a
  contract (a verifier refusal, a property, an output), never an SSA name or
  an op order the change does not decide. Each §7 bug you own gets the
  discriminating fixture the README names.
- **No commits, no pushes, no git writes.** The coordinator integrates.
- **Handoff** (your final message, compact): changed paths, each mapped to an
  obligation; for each finding, its representation line (the state made
  unrepresentable, the check moved to a boundary, the branch deleted, or why
  a case is essential) and a count of branches, guards and checks removed;
  contracts supplied; consumer adaptations made and any listed adaptation
  that was a false match; hub text the coordinator must apply; checks
  actually run with their results, or NotRun; unresolved seams, each with
  its evidence.
