<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane L02 (effects-rows): rows, derivation, functions and calls

**Exclusive write:** `compiler/spec/IdrisMLIR/Spec/Functions/`,
`foreign/idr/lib/IR/Func/`, `foreign/idr/include/idr/IR/Func.h`,
`foreign/idr/lib/Analysis/Effects.cpp`,
`foreign/idr/include/idr/Analysis/Effects.h`,
`foreign/idr/lib/Transforms/Effects/`,
`foreign/idr/include/idr/Transforms/Effects.h`.

**Read deeply:** P0 §5.1 (upstream, the e-graph and LLVM; landing) and
§5.5 (tail position one fact); in §2 D9, D10, D22, D29, D30, D61, D93,
D94, D102; in §3 C2, C64, C72, C73, C139. Your verification report
`audits/p0/verify/L02-effects-rows.md` in full. The audits: 02, 05, 12;
`design/effects.md` §3 to §8; `design/effect-vocabulary.md` §4.3 to §7,
§8.3; `design/typed-effects.md`; `design/lifetimes/lowering.md` §4.4,
§4.5; wave1 §5.1, §5.3. Code: `lib/IR/Func/`, `include/idr/IR/Func.h`,
`include/idr/Analysis/Effects.h`, `lib/Transforms/Effects/`; upstream's
CSE, LICM utilities, `ControlFlowSink.cpp`, `isOpTriviallyDead`, the
inliner's effect queries, `InliningUtils.cpp`.

**Also cited by your area** (§3 decisions that name your verification report; implement what falls in your paths, leave the rest to their owners): C20, C31, C41, C69, C70, C74.

**Also yours:** C8: every suspected bug of P0 §8 whose code lies in your paths.

**Contract:** a computation's row lives on its op (`idr.func`,
`idr.call`), never in a value type; one derivation from the ops, held to
it by the verifier per function; a call carries its callee's row. Seams
fixed here: `idr.call`'s verifier calls `idr::tail::verify(CallOp)`,
declared in `include/idr/IR/Tail.h` by L10, and `idr.func`'s region verifier calls `idr::tail::verify(FuncOp)` (one walk of the tail spine, C20); the inliner's call
conversion creates L05's `idr.lifetime.forget` for a `view` parameter.

**End state:** `Spec.Functions` declares `idr.func` and `idr.call`: the
derived row (D22, D29); the per-parameter record, with D61's write part
on an exclusive owned parameter and D94's amount (`Finite n |
Unbounded`) on a put-kind lifetime parameter, each existing only where
the parameter's type admits it; lifetime kinds in the signature (D93);
the call's tail fact slot (D30, C139), whose meaning L10 owns. The
derivation and its verifier are one template; the inliner interface maps
lifetime arguments (D93: `view` accepts any kind).

**Recipe:**
- Write `Spec.Functions` and the ops' C++ in `lib/IR/Func/`.
- Write the one derivation (callees first) and its per-function verifier;
  rows re-derived as C64 says.
- The call rule (D93): a lifetime operand's kind equals its parameter's,
  or the parameter is `view`; that is the call's type check.
- D102: a call may be deleted or floated only when its row carries
  neither `crash` nor `divergence`; expose that as the query the e-graph
  and dead code read.
- Hand L21 the row-to-LLVM mapping through L01's table, never your own.

**Delete:** every second reading of a function's effects in your files;
the summary bits read apart from the ops (02 §3.7); `Idr_Effect`'s hand
summary.

**QTT:** the per-parameter parts exist only where the parameter's grade
or kind admits them, so no part can sit on a parameter it does not
describe.

**NOT TO DO:** the effect tree and forms (L01); tail position's decider
(L10); lifetime ops (L05); LLVM attributes (L21).

**Acceptance:** INT finds every function's row derived and verified, a
call's row its callee's, and the program suite unchanged except as
rulings change it.

**Stop and return:** when the ops, the derivation, the verifier and the
inliner hooks are written and your handoff is sent.

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
