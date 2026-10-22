# Lane L09 (control-flow): regions, matches, join points

**Exclusive write:** `compiler/spec/IdrisMLIR/Spec/Control/`,
`foreign/idr/lib/IR/{Flow,FlowEdges,FlowOps,Regions,OpsMatch,OpsMatchSyntax}.cpp`,
`foreign/idr/include/idr/IR/{Flow,FlowEdges}.h`,
`foreign/idr/lib/Transforms/Joins/`,
`foreign/idr/include/idr/Transforms/Joins.h` (the one construction of join groups),
`foreign/idr/lib/Conversion/Matches.cpp`,
`foreign/idr/include/idr/Conversion/Matches.h`.

**Read deeply:** P0 §5.3 (the dialect's control flow) whole; in §2 D18,
D19, D25, D76, D82, D105; in §3 C65, C93, C94, C139, C157. Your
verification report `audits/p0/verify/L09-control-flow.md` in full. The
audits: 03 §5.2; 04; 10; `design/match-and-counting.md` whole; wave1
§5.1, §5.4, §5.9; synthesis A §5.8. Code: the match ops and their
implementation, `Transforms/Optimize/Contify.cpp`, `lib/IR/Canon/`,
`Transforms/Tail/{TailLoops,Trmc}.cpp`; PR #166688 (`gh pr diff 166688 -R
llvm/llvm-project`, read only) against the pin's control-flow interfaces.

**Also cited by your area** (§3 decisions that name your verification report; implement what falls in your paths, leave the rest to their owners): C19, C20, C41, C45, C48, C95.

**Contract:** a match is a region per case rejoining at the op's results,
from the frontend to the lowering; each case binds its scrutinee refined
to that case's constructor, and fields are reads of it (D105); a join
point is a continuation local to its function, jumped to with typed
arguments, never an allocated closure, typed with upstream's builtin
`token` (D76) and upstream's early exit (PR #166688, carried by L06);
blocks appear only at the lowering, through upstream's
`convert-scf-to-cf`.

**End state:** `Spec.Control` declares the match, the literal match,
yield, join points and loops; their C++ implements
`RegionBranchOpInterface`; structure loops make recursive join points
loops; matches lower through `scf` and upstream's conversion.

**Recipe:**
- Write the ops and interfaces as P0 §5.3 and your report §5 draft them.
- Change the case binding per D105.
- Remove each canonicalization pattern on your ops (D98); their rewrites
  (C65's loop to join among them) become rules as data in your spec
  module (C157).

**Delete:** the three enclosing-match walks, the poison yields,
case-of-case's whole-consumer copy (it becomes the e-graph's choice per
arm), contification's single-site rule in your files.

**QTT:** a join point's typed arguments carry grades and reuse tokens; a
linear continuation is called once, by its type.

**NOT TO DO:** tail position and frames (L10); contification's pass
(L18's `Optimize/Contify.cpp`, written against your ops); the e-graph
(L14).

**Acceptance:** INT finds every match a region per case through the
pipeline, blocks only after `convert-scf-to-cf`, and the 1,347 wrongly
decided matches of `workloads.md` impossible to write.

**Stop and return:** when the control-flow ops and their lowering are
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
  an enum case, never a `bool`; no `assert` (D91): an invariant is a
  type, a verifier rule, or nothing; no pointer-keyed map holding
  per-node state; nothing static built per function.
- Idris: in the subset both hosts compile, type-driven (indices, views,
  erased proofs, evidence over `Bool`, C154: evidence at quantity 0 in
  bodies the stock host runs). On the stock host, avoid until fixed:
  constructors named `Nil`, `::` or `#` matched inside pattern lambdas,
  nested linear `LPair`s (`audits/p0/design/idris-linear-check.md`), and
  an effectful `let` whose value the body ignores
  (`audits/p0/design/idris-identity-bug.md`).
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
