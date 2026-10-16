<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
## Common obligations (every lane)

- **The packet is the contract.** `proposals/0003-self-host/checker/README.md` (the
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
- **Hard cutover, zero backwards compatibility (the owner's rule).** The new
  representation replaces the old one in the same change, everywhere in your
  writes: no shim, alias, re-export, deprecated name, wrapper keeping an old
  signature, dual code path, fallback to the old form, compatibility flag,
  "legacy" branch, or comment promising a later removal. Old formats, option
  names and file layouts are not kept readable. A consumer outside your writes
  is named in your handoff for its owner to cut over, never served by a
  bridge you keep.
- **Upstream MLIR first, our C++ at its minimum (the owner's rule).** This
  project is idris-mlir: an MLIR compiler for Idris, not a superoptimizer of
  its own. Before writing C++, find the upstream mechanism and use it: ODS
  and its constraints, interfaces and traits, declarative patterns,
  upstream passes and their options, `PassInstrumentation`, actions and
  `DebugCounter`, `verifyRoundtrip`, the reducer interface, LLVM's
  statistics. Prefer declaring in TableGen to writing in C++; prefer deleting
  our C++ an upstream mechanism replaces to adding any; a new C++ abstraction,
  helper or generator states in its comment why no upstream mechanism fits.
  Where this pulls against an optimization, the smaller C++ wins unless your
  dispatch names the optimization.
- **Program with the types (Idris 2, after Brady; the owner's rule,
  2026-10-16).** Read `.claude/skills/representation-first/SKILL.md`, the
  section "Program with the types: Idris 2, not Haskell", before your first
  edit:
  - index the invariant;
  - decide with evidence, never a `Bool`;
  - keep proofs and indices at quantity 0;
  - return the value with what was learned;
  - use one record, never parallel lists;
  - use `List1` where empty would be an error;
  - use views and `with`.

  Stay inside the subset idris-mlir compiles. Your handoff names each
  branch or lookup the types removed.
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
  - Idris: a private copy under `/tmp/0003c-<lane>/`, taken from the base
    commit, never from the live tree, which sibling lanes are writing:
    `git archive 1380a9d0 compiler tests | tar -x -C /tmp/0003c-<lane>/`.
    `compiler/` and `tests/` are unchanged from that commit at dispatch, so
    it is also HEAD's frontend for every comparison. It is checked or built
    there by
    the pinned `.toolchain/idris2/bin/idris2` with
    `IDRIS2_PREFIX=.toolchain/idris2` and `IDRIS2_PACKAGE_PATH` naming
    `build/idris2-host/idris2-0.8.0` (the fork, as `make typecheck` installed
    it). Code that runs on the stock host (a generator, a property, a model)
    is also run there, on Chez: that is real evidence, report it. A module of
    a sibling lane that your module imports and that is not in the tree yet
    is stubbed in your private copy only, with exactly the packet's
    signatures (§4) and `?holes` for bodies: packet-local glue, never
    written to the tree, never your deliverable. Your own module typechecks
    against those stubs with totality enforced.
  Behaviour of idris-mlir and idris-mlir-opt is the owner's build after
  integration; every new or changed test this machine cannot run carries a
  first-line `NEEDS-ACCEPTANCE:` mark saying what to confirm.
- **Tests.** A brittle test is deleted, never restated. A test states the
  checker's contract: a program refused, with the cycle its message names,
  or admitted and compiled as before. Never the text of an internal graph.
- **The frontend runs here.** Build your private frontend in
  `/tmp/0003c-<lane>/` with the pinned Idris and run it on Chez over the
  programs your acceptance names (`tests/programs`, `tests/accept`,
  `tests/reject`, the self compile's sources). Compare it with HEAD's
  frontend built the same way: status, stdout, stderr and Core dump. That
  run is behavioural evidence. **The backdoor is banned:** no frontend
  patched to admit a refusal may produce evidence for any gate.
- **No commits, no pushes, no git writes.** The coordinator integrates.
- **Handoff** (your final message, compact): changed paths, each mapped to an
  obligation; for each obligation, its representation line (the guideline's
  last bullet: the state made unrepresentable, the check moved to a boundary,
  the branch deleted, or why the case is essential); contracts supplied; consumer adaptations made; hub text the
  coordinator must apply; checks actually run with their results, or NotRun;
  unresolved seams, each with its evidence.
