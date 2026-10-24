<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane L06 (toolchain-upstream): the toolchain, carried patches, pins

**Exclusive write:** `tools/`, `upstream/`, `PINS.md`,
`toolchain.lock.json`, `.gitmodules`.

**Read deeply:** P0 §7 S0 and S3; in §2 D25, D56, D76, D91, D99 and every
ruling naming a patch (D18, D25, D43, D82); in §3 C5, C10, C33, C35, C43, C93, C99 (the recursion families shown to scale with the input, the rest left for INT's stack painting; D33's owed patch for `upstream/10-recursive-attribute-parser`), C100 (two snmalloc patches), C108 (27 and 64, under D43), C114 (two patches), C120, C149; not C48's (superseded by D98) or C151's (only if measured). AGENTS.md's "Upstream
and pins" and "The targets and the build" (the weekly fast-forward).
Your verification report `audits/p0/verify/L06-dispositions.md`, and
`L09-control-flow.md` and `L14-analyses.md` for PR #166688 and the
call-graph patch. `upstream/README.md`;
`audits/p0/design/idris-identity-bug.md`;
`audits/p0/design/idris-linear-check.md`; `design/perf-sources.md` U8.
Code: `tools/bootstrap.sh` whole, `tools/patches.sh`,
`tools/verify-pins.sh`, `tools/upstream-idris/`, every `upstream/*/`.

**Also cited by your area** (§3 decisions that name your verification report; implement what falls in your paths, leave the rest to their owners): C11, C12, C22, C27, C53, C59.

**Also yours** (rulings and decisions no brief named before): C141; and C8: every suspected bug of P0 §8 whose code lies in your paths.

**Contract:** every dependency fast-forwarded to its latest (LLVM and
MLIR, modular and Idris 2 at main; every other to its latest release),
carried patches rebased or dropped where upstream has them; the
toolchain's LLVM and MLIR built without assertions in every stage our
code compiles against or links (D91; today ON at `bootstrap.sh:1028`,
`:1131`). A patch lives as `upstream/<bug>/<project>.patch` with its
report, reproducer, plan to upstream and `PINS.md` entry; its
`tests/upstream-<bug>` check is L19's, from the list below.

**End state:** carried, each complete: PR #166688 rebased by hand with
C93's five fixes (D25); the `mlir::CallGraph` patch (C33); the
`DataFlowSolver` storage patch (S3); FuncToLLVM keeping argument
attributes such as `noalias` on expanded memref arguments (C149); the
stock Idris inliner fix (`idris-identity-bug.md`) recorded as a report
with its patch, carried when a library body reaches it. Retired: patches
06, 28, 63 and any that reach nothing (C35). The lock and bootstrap
updated; the Idris 2 gitlink move is the coordinator's git operation,
written in your handoff as the commit to point at.

**Recipe:**
- Update `toolchain.lock.json` and `bootstrap.sh` (assertions off;
  patches applied in order); check `tools/` for `assert`-dependent flags.
- Write each patch directory in upstream's form, upstream's own fix first.
- Update `PINS.md` for every change P0 records: the patches above, the
  fork's changes (D101's `WithBounds` sum; the fork items of L17's
  handoff, written as P0 names them), retired entries.
- Delete `tools/profile.sh`'s Python (its replacement is L19's harness).

**Delete:** the retired patches and their `PINS.md` lines; assertion
flags; stale pins.

**QTT:** C149's patch is what carries a linear buffer's `noalias` to
LLVM; its reproducer shows the attribute surviving.

**NOT TO DO:** tests (L19); any code under `foreign/`, `compiler/`,
`runtime/`, `libs/`; git operations.

**Acceptance:** INT's bootstrap applies every patch to the new pins and
builds with assertions off on the four targets; `tools/verify-pins.sh`
passes.

**Stop and return:** when the lock, bootstrap, patches and `PINS.md` are
written and your handoff is sent.

## Common obligations (every lane)

**What this swarm is.** The P0 cutover itself: the implementation of
`proposals/0000-mlir-native.md`, written whole by twenty-one owned lanes
at once and an integration lane, in place, on `main`.
It is one change (D56: "we will only build when this entire cutover is
fully done"): no lane builds, typechecks or runs its part; the
integration lane (INT) builds, runs and qualifies the whole on the four
targets and routes every failure back to the lane that owns it. It is a
hard cutover (D6, AGENTS.md): the new form replaces the old in the same
change, with no shim, alias, re-export, dual path, fallback, flag or
"remove later", and the dead code, tests and comments it leaves are
deleted.

**Read first, in full, before any edit:**
1. `.claude/skills/representation-first/SKILL.md` (the lens every change
   is judged by), and `.claude/skills/testing-by-search/SKILL.md` before
   touching a test.
2. `AGENTS.md` (the rules; the owner's dated rulings are quoted there).
3. `proposals/0000-mlir-native.md`, the whole document: §2 holds the
   owner's rulings D1 to D109, which bind you; §3 the coordinator's
   decisions C1 to C157, which bind you unless you show the coordinator a
   contradiction; §5 the target by area, the canonical contract every
   lane writes against; §6 what goes; §7 the order.
4. Your verification report, `audits/p0/verify/LNN-*.md` (named in your
   lane): its §2 (boundaries, provenance, seams) and §5 (work units) are
   the drafted recipe for your area, written before the rulings after
   it; where a later ruling or decision differs, the later one governs.
5. The design documents your lane names, then the code you own and the
   code that consumes it.
6. Every contract under `audits/p0/verify/parts/contracts/`: shared
   declarations the lanes fixed while working (the specification's Core
   vocabulary and the pass list among them), binding as P0 §5 is.

**The engagement contract.**
- Checkout `/Users/bjorn/Documents/idris-mlir`, branch `main` (the owner, 2026-10-21: "we should do everything on main").
  Record `git rev-parse --short HEAD` when you start and when you finish.
- Write only inside your **exclusive write** paths (`ownership.json`); a
  new file goes only inside a directory you own. Every other path is
  another writer's: the other lanes, INT, and the coordinator
  (`proposals/`, `AGENTS.md`, `audits/`, `.claude/`). Never edit
  `third_party/` or `sources/`.
- No build, no typecheck, no test run, no generator run, no `make` target
  of any kind, and never `make bootstrap`, `tools/bootstrap.sh`,
  `make build`, `make test*`, `make self` or `make compile` (D56; this
  machine does not build LLVM). Reading, `grep`, `find`, `wc`, `git log`,
  `git show` and `git diff` are fine. No git write: the coordinator
  commits.
- Four first-class targets (AGENTS.md): nothing per-target outside the
  target's entry.

**Shared contracts.** P0 §5 fixes every shared declaration by name and
shape: the specification's ops, types and attributes, the grade
(`!idr.graded<uses, hold, T>`, D88 to D90), the lifetime
(`!idr.lifetime<view | room | cursor | home k>` and its openers, D93),
families (`!idr.data<#Family[...]>`, D48), the effect tree and its one
query API (D9, D27 to D29), the solver layer's shared types (C114), the
tail fact on `idr.call` (D30, C139), the runtime's one ending table
(D37, D64, D81) and the pipeline as one generated list (C28). Write
against those names and shapes as P0 states them, whoever owns the file
that declares them; never declare your own copy, and never wait for the
owner's file to land. Where you need a declaration P0 does not fix,
report the exact seam to the coordinator and continue with everything
else.

**Hub files.** Every `CMakeLists.txt` outside a directory you own, the root `Makefile` and
`CMakeLists.txt`, and the generated outputs (`include/idr/IR/Generated/`,
`generated.manifest`) are INT's. Do not edit them: list in your handoff
each file you added, moved or deleted, per directory, and INT wires
them.

**How the code is written.**
- C++: concept-constrained templates, monomorphized; dispatch over ops
  only through MLIR (an interface, a trait, a rooted pattern), never an
  `isa<A, B>` ladder or a concept that lists ops; a choice is a type or
  an enum case, never a `bool`; invariants asserted freely, always on
  (D114, D115, C226), C++26 contracts once clang has them; no
  pointer-keyed map holding per-node state; nothing static built per
  function.
- Idris, D112: no run-time check of our own invariant (`internal`,
  `assert_total`, `assert_smaller`, `believe_me`): the state is made
  unrepresentable or its proof carried; code is never kept worse to
  spare the compiler (D113).
- Idris: in the subset both hosts compile, type-driven (indices, views,
  erased proofs, evidence over `Bool`, C154: evidence at quantity 0 in
  bodies the stock host runs). Where the stock host gets correct Idris
  wrong (a parse its grammar allows, a crash, a miscompile), the code is
  not bent around it: the bug is reported to the coordinator, and L06
  patches stock Idris (`upstream/<bug>/idris.patch`, D121). A slip of
  ours against the language's rules (a lowercase global in a type, which
  Idris binds as a fresh implicit; a missing import) is ours to fix.
- Comments explain why the code is the way it is; they cite no document
  or rule number. Names are churned until correct (D90's vocabulary).

**Verification you may do.** Read-only checks only: every symbol you
delete has no remaining reference inside your paths (`grep`), and each
reference outside them is listed in your handoff as a seam for its
owner. INT runs the checks AGENTS.md names (`make check`, `make build`,
`make test`, `make test-idr`, `make test-unit`, `make test-mlir-tools`)
on the whole.

**Handoff.** When your obligations are done, reply in under 400 words:
the paths you changed, per obligation; per obligation, the state made
unrepresentable, the check moved to a boundary or the branch deleted,
or why the case is essential (AGENTS.md); the files added, moved or
deleted per directory, for INT; every unresolved seam, with its owner;
HEAD at start and at finish.

**The owner's word over the coordinator's.** The owner, 2026-10-21: "my
human word always takes precedence over automated decisions." The
rulings bind you; a coordinator decision that the evidence shows wrong
is reported to the coordinator, never changed by you. Escalate
conflicting evidence with the contract change you propose, and keep
working on every obligation it does not block.

## The six binding rules (verbatim)

1. Do exactly the assigned obligations and the necessary consumer adaptations within the exclusive write set. Every changed hunk, new file, dependency or abstraction must map to a named obligation. If the contract cannot be completed within those writes, report the exact missing seam; do not silently widen scope.
2. Add no unsolicited features, frameworks, generic helpers, configuration knobs, retries, telemetry, documentation, dependencies, formatting sweeps or neighboring cleanup. Elegance means completing the selected representation and deleting its named predecessor, not opening another project.
3. Do not be afraid to duplicate reading, investigation, reasoning or small, packet-local, non-authoritative glue. Do not wait for a sibling just to avoid that duplication, and do not introduce a shared helper that creates a false dependency. Reuse repairs that have already landed; duplicated investigation does not mean rebuilding working mechanisms.
4. Authoritative schemas, vocabularies, identities and business facts still have exactly one owner. Never duplicate them, create competing implementations or write concurrently to another owner's file. Duplicate effort is allowed; duplicate authority and overlapping writes are not.
5. Finish the bounded deliverable, report changed paths against obligations, the checks actually run and any unresolved seams, then return control. Do not roam into another packet, manufacture work to keep up the headcount, or build a reporting or coordination platform.
6. User steering goes through the coordinator, into the affected packet only. The coordinator corrects an architectural contradiction in the canonical contract and re-dispatches the affected lane. No lane stops for it.
